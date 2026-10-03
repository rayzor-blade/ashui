package ashui.core.render;

/**
	Signed distances and coverage for UI primitives, imported by the UI
	shaders. Ports of Blinc's `sdf_core.wgsl` helpers; distances are in
	pixels, negative inside.
**/
class Sdf implements #if ashui_caribou caribou.hxsl.Shader #else hlwgpu.hxsl.Shader #end {
	static var SRC = {
		/** Corner `i` of the two triangles of an instance's quad, in 0..1. **/
		function quadCorner(i : Int) : Vec2 {
			var c = vec2(0., 0.);
			if (i == 1 || i == 3)
				c = vec2(1., 0.);
			if (i == 2 || i == 5)
				c = vec2(0., 1.);
			if (i == 4)
				c = vec2(1., 1.);
			return c;
		}

		/** Where a point `rel` from a box's top-left lands on screen: the box's screen top-left `at` plus `rel` through the 2x2 `m`. **/
		function placed(at : Vec2, m : Vec4, rel : Vec2) : Vec2 {
			return at + vec2(m.x * rel.x + m.z * rel.y, m.y * rel.x + m.w * rel.y);
		}

		/** A pixel position, y down, as clip space. **/
		function pixelToClip(pos : Vec2, size : Vec2) : Vec4 {
			return vec4(pos.x / size.x * 2. - 1., 1. - pos.y / size.y * 2., 0., 1.);
		}

		/** Distance to a box at `origin` of `size`, its corners rounded top-left, top-right, bottom-right, bottom-left. **/
		function sdRoundedRect(p : Vec2, origin : Vec2, size : Vec2, radius : Vec4) : Float {
			var halfSize = size * 0.5;
			var rel = p - (origin + halfSize);
			var q = abs(rel) - halfSize;
			var r = radius.w;
			if (rel.y < 0.) {
				r = radius.x;
				if (rel.x > 0.)
					r = radius.y;
			} else if (rel.x > 0.) {
				r = radius.z;
			}
			r = min(r, min(halfSize.x, halfSize.y));
			var qa = q + vec2(r, r);
			return length(max(qa, vec2(0., 0.))) + min(max(qa.x, qa.y), 0.) - r;
		}

		/**
			Distance to a box whose corners each follow a superellipse of
			`shape`'s `n`: 1 round, 2 squircle, 0 bevel, -1 scoop, 100 or more
			square, -100 or less notch. Blinc's `sd_shaped_rect`, with a scoop
			centred on the corner's tip as CSS draws it and distances that are
			continuous and a pixel per pixel, for even edges and borders.
		**/
		function sdShapedRect(p : Vec2, origin : Vec2, size : Vec2, radius : Vec4, shape : Vec4) : Float {
			var halfSize = size * 0.5;
			var rel = p - (origin + halfSize);
			var q = abs(rel) - halfSize;
			var r = radius.w;
			var n = shape.w;
			if (rel.y < 0.) {
				r = radius.x;
				n = shape.x;
				if (rel.x > 0.) {
					r = radius.y;
					n = shape.y;
				}
			} else if (rel.x > 0.) {
				r = radius.z;
				n = shape.z;
			}
			r = min(r, min(halfSize.x, halfSize.y));
			var qa = q + vec2(r, r);
			// The box with sharp corners.
			var box = length(max(q, vec2(0., 0.))) + min(max(q.x, q.y), 0.);
			var d = 0.;
			if (n <= -100.) {
				// A notch: the box less everything beyond the corner's step, whose only edges are the step's two faces.
				var cut = length(max(-qa, vec2(0., 0.))) + min(max(-qa.x, -qa.y), 0.);
				d = max(box, -cut);
			} else if (abs(n - 1.) < 0.01) {
				d = length(max(qa, vec2(0., 0.))) + min(max(qa.x, qa.y), 0.) - r;
			} else if (n < 0.) {
				// A scoop: the box less a superellipse centred on the corner's tip.
				d = max(box, -superellipse(-q, r, n));
			} else if (n >= 100.) {
				d = box;
			} else if (abs(n) < 0.01) {
				// A bevel: the box cut by the chamfer's half-plane.
				d = max(box, (qa.x + qa.y - r) * 0.70710678);
			} else {
				// The corner lies inside the box, so it is never deeper than the box.
				d = max(box, superellipse(qa, r, n));
			}
			return d;
		}

		/**
			Signed distance from `v`, at least 0 in both axes, to a quarter
			superellipse of radius `r` and exponent `2^|n|` about the origin. The
			norm is divided by its gradient's length, so the value moves a pixel
			per pixel and edges and borders have the same width at every `n`.
		**/
		function superellipse(v : Vec2, r : Float, n : Float) : Float {
			var e = pow(2., min(abs(n), 5.));
			// Kept off zero: WGSL's pow(0, 0) is undefined, and a bevel's e - 1 is 0.
			var t = max(v / max(r, 0.001), vec2(0.000001, 0.000001));
			// The larger component is factored out: t^e alone underflows f32 once e reaches 8.
			var m = max(t.x, t.y);
			var u = t / m;
			var norm = m * pow(pow(u.x, e) + pow(u.y, e), 1. / e);
			var grad = vec2(pow(min(t.x / norm, 1.), e - 1.), pow(min(t.y / norm, 1.), e - 1.));
			return (norm - 1.) * r / max(length(grad), 0.0001);
		}

		/** Distance to the inside of a quarter ellipse, for a border's inner corner. **/
		function quarterEllipseSdf(point : Vec2, radii : Vec2) : Float {
			var safe = max(radii, vec2(0.001, 0.001));
			return (length(point / safe) - 1.) * (safe.x + safe.y) * -0.5;
		}

		/** The error function, to Abramowitz and Stegun 7.1.26. **/
		function erf(x : Float) : Float {
			var a = abs(x);
			var t = 1. / (1. + 0.3275911 * a);
			var y = 1. - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * exp(-a * a);
			return sign(x) * y;
		}

		/**
			How much of the pixel at `p` on screen the screen clip leaves; it is
			there when `clips` has bit 1. Its rounded corners have shape `n`, the
			clipping parent's, so a squircle parent clips to its own curve.
		**/
		function clipCoverage(p : Vec2, bounds : Vec4, radii : Vec4, clips : Float, n : Float) : Float {
			var alpha = 1.;
			if (clips - 2. * floor(clips * 0.5) > 0.5)
				alpha = 1. - smoothstep(-0.75, 0.75, sdShapedRect(p, bounds.xy, bounds.zw, radii, vec4(n, n, n, n)));
			return alpha;
		}

		/**
			How much of the point `p`, in the primitive's own coordinates, its
			local clip leaves; it is there when `clips` has bit 2. `aa` is half a
			screen pixel in those coordinates.
		**/
		function localClipCoverage(p : Vec2, bounds : Vec4, radii : Vec4, clips : Float, n : Float, aa : Float) : Float {
			var alpha = 1.;
			if (clips > 1.5)
				alpha = 1. - smoothstep(-aa, aa, sdShapedRect(p, bounds.xy, bounds.zw, radii, vec4(n, n, n, n)));
			return alpha;
		}

		/**
			How much of the point `p`, on screen, a clip that fades what it
			clips leaves: a linear ramp from nothing at each edge of `bounds`
			to all of it `fade` in, top, right, bottom, left; 0 is no fade.
		**/
		function fadeCoverage(p : Vec2, bounds : Vec4, fade : Vec4) : Float {
			var alpha = 1.;
			if (fade.x > 0.)
				alpha *= clamp((p.y - bounds.y) / fade.x, 0., 1.);
			if (fade.y > 0.)
				alpha *= clamp((bounds.x + bounds.z - p.x) / fade.y, 0., 1.);
			if (fade.z > 0.)
				alpha *= clamp((bounds.y + bounds.w - p.y) / fade.z, 0., 1.);
			if (fade.w > 0.)
				alpha *= clamp((p.x - bounds.x) / fade.w, 0., 1.);
			return alpha;
		}

		/** Half a screen pixel, measured in the coordinates `p` is in. **/
		function halfPixel(p : Vec2) : Float {
			return 0.25 * (length(dFdx(p)) + length(dFdy(p)));
		}
	};
}
