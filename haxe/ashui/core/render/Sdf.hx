package ashui.core.render;

/**
	Signed distance functions for UI shapes, and the coverage helpers built
	on them, imported by every UI shader. A signed distance function gives
	a point's distance to a shape's edge, in pixels: negative inside,
	positive outside, 0 on the edge. A shader turns it into how much of a
	pixel the shape covers with a `smoothstep` across about a pixel either
	side of 0, which anti-aliases the edge at any size or rotation; a
	border is the band between two distances, and a shadow a blur of one.
	Ported from Blinc's `sdf_core.wgsl`.
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
			Distance to a box whose corners each follow a superellipse, its
			corner shape `n` from `shape` (see `ashui.types.CornerShape`): 1
			round, 2 squircle, 0 bevel, -1 scoop, 100 or more square, -100 or
			less notch. A scoop is centred on the corner's tip as CSS draws
			it, and distances are continuous and move a pixel per pixel, so
			edges and borders are even. Ported from Blinc's `sd_shaped_rect`.
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
			if (r <= 0.) {
				// No corner to shape: a superellipse of no radius is 0 everywhere, which would halve the coverage inside.
				d = box;
			} else if (n <= -100.) {
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

		/** Distance to a record's box of `size` from the origin: its notch when it has one (see `sdNotch`), else its shaped, rounded box. **/
		function boxDistance(p : Vec2, size : Vec2, radius : Vec4, shape : Vec4, corners : Vec4, top : Vec4, bottom : Vec4) : Float {
			var d = 0.;
			if (isNotch(corners, top, bottom))
				d = sdNotch(p, size, corners, top, bottom);
			else
				d = sdShapedRect(p, vec2(0., 0.), size, radius, shape);
			return d;
		}

		/** Distance to the ellipse about `c` of radii `radii`, scaled by its smaller radius. **/
		function sdEllipseAt(p : Vec2, c : Vec2, radii : Vec2) : Float {
			return (length((p - c) / max(radii, vec2(0.001, 0.001))) - 1.) * min(radii.x, radii.y);
		}

		/** Distance to triangle `abc`. **/
		function sdTriangle(p : Vec2, a : Vec2, b : Vec2, c : Vec2) : Float {
			var e0 = b - a;
			var e1 = c - b;
			var e2 = a - c;
			var v0 = p - a;
			var v1 = p - b;
			var v2 = p - c;
			var pq0 = v0 - e0 * clamp(dot(v0, e0) / max(dot(e0, e0), 0.000001), 0., 1.);
			var pq1 = v1 - e1 * clamp(dot(v1, e1) / max(dot(e1, e1), 0.000001), 0., 1.);
			var pq2 = v2 - e2 * clamp(dot(v2, e2) / max(dot(e2, e2), 0.000001), 0., 1.);
			var s = sign(e0.x * e2.y - e0.y * e2.x);
			var d = min(min(vec2(dot(pq0, pq0), s * (v0.x * e0.y - v0.y * e0.x)), vec2(dot(pq1, pq1), s * (v1.x * e1.y - v1.y * e1.x))),
				vec2(dot(pq2, pq2), s * (v2.x * e2.y - v2.y * e2.x)));
			return -sqrt(d.x) * sign(d.y);
		}

		/** The union of two distances, blended over `k`. **/
		function smin(a : Float, b : Float, k : Float) : Float {
			var h = clamp(0.5 + 0.5 * (b - a) / k, 0., 1.);
			return mix(b, a, h) - k * h * (1. - h);
		}

		/** The intersection of two distances, blended over `k`. **/
		function smax(a : Float, b : Float, k : Float) : Float {
			return -smin(-a, -b, k);
		}

		/**
			Whether a record is a notch: any of its notch rows set. Its box is
			drawn by `sdNotch` instead of `sdShapedRect`.
		**/
		function isNotch(corners : Vec4, top : Vec4, bottom : Vec4) : Bool {
			return dot(abs(corners), vec4(1., 1., 1., 1.)) + top.x + bottom.x > 0.;
		}

		/**
			Distance to a notch filling `size` from the origin: a rounded box
			whose corners with a negative radius are concave, flaring out to
			the box's edge as a macOS menu-bar dropdown meets its bar, and whose
			top and bottom edges may carry a modifier at their centre, each
			(kind, width, height, corner radius): 1 a scoop, 2 a bulge, 3 a cut,
			4 a peak. Ported from Blinc's `sd_notch`.
		**/
		function sdNotch(p : Vec2, size : Vec2, corners : Vec4, top : Vec4, bottom : Vec4) : Float {
			var r = abs(corners);
			var tlC = corners.x < 0.;
			var trC = corners.y < 0.;
			var brC = corners.z < 0.;
			var blC = corners.w < 0.;
			// Bulges and peaks protrude past their edge, so the body is inset by their height.
			var topH = 0.;
			if ((top.x > 1.5 && top.x < 2.5) || (top.x > 3.5 && top.x < 4.5))
				topH = top.z;
			var botH = 0.;
			if ((bottom.x > 1.5 && bottom.x < 2.5) || (bottom.x > 3.5 && bottom.x < 4.5))
				botH = bottom.z;
			var tl = 0.;
			if (tlC) tl = r.x;
			var tr = 0.;
			if (trC) tr = r.y;
			var br = 0.;
			if (brC) br = r.z;
			var bl = 0.;
			if (blC) bl = r.w;
			var left = max(tl, bl);
			var right = max(tr, br);
			var topOffset = max(max(tl, tr), topH);
			var bottomOffset = max(max(bl, br), botH);
			var innerOrigin = vec2(left, topOffset);
			var innerSize = vec2(max(size.x - left - right, 0.001), max(size.y - topOffset - bottomOffset, 0.001));
			// Concave corners are square on the body; their curve is the flare.
			var innerRadii = r;
			if (tlC) innerRadii.x = 0.;
			if (trC) innerRadii.y = 0.;
			if (brC) innerRadii.z = 0.;
			if (blC) innerRadii.w = 0.;
			var d = sdShapedRect(p, innerOrigin, innerSize, innerRadii, vec4(1., 1., 1., 1.));
			var innerRight = innerOrigin.x + innerSize.x;
			var innerBottom = innerOrigin.y + innerSize.y;
			// A flare's edge lies along the body's and its curve meets the body's side
			// tangentially, so it joins with a plain min: a smooth one would bulge the shared edge.
			// Each piece added to the body reaches this far into it, hidden there, so no point near where they meet
			// is near an edge of both: the union's distance inside is to the outline, and a border follows only that.
			var into = min(innerSize.x, innerSize.y) * 0.5;
			// A flare needs only a short reach: a long one's far end, inside the body, still bends the gradient glass refracts along.
			var flareInto = min(8., into);
			// A flare too tall for the box squashes into an ellipse rather than overflowing.
			var room = max(size.y - topOffset - bottomOffset, 0.);
			var sharp = vec4(0., 0., 0., 0.);
			var round = vec4(1., 1., 1., 1.);
			if (tlC) {
				var ry = min(r.x, room);
				var flare = max(sdShapedRect(p, vec2(0., innerOrigin.y), vec2(left + flareInto, ry), sharp, round),
					-sdEllipseAt(p, vec2(0., innerOrigin.y + ry), vec2(left, ry)));
				d = min(d, flare);
			}
			if (trC) {
				var ry = min(r.y, room);
				var w = size.x - innerRight;
				var flare = max(sdShapedRect(p, vec2(innerRight - flareInto, innerOrigin.y), vec2(w + flareInto, ry), sharp, round),
					-sdEllipseAt(p, vec2(size.x, innerOrigin.y + ry), vec2(w, ry)));
				d = min(d, flare);
			}
			if (brC) {
				var ry = min(r.z, room);
				var w = size.x - innerRight;
				var flare = max(sdShapedRect(p, vec2(innerRight - flareInto, innerBottom - ry), vec2(w + flareInto, ry), sharp, round),
					-sdEllipseAt(p, vec2(size.x, innerBottom - ry), vec2(w, ry)));
				d = min(d, flare);
			}
			if (blC) {
				var ry = min(r.w, room);
				var flare = max(sdShapedRect(p, vec2(0., innerBottom - ry), vec2(left + flareInto, ry), sharp, round),
					-sdEllipseAt(p, vec2(0., innerBottom - ry), vec2(left, ry)));
				d = min(d, flare);
			}
			d = notchEdge(p, d, size.x * 0.5, innerOrigin.y, top, 1., into);
			d = notchEdge(p, d, size.x * 0.5, innerBottom, bottom, -1., into);
			return d;
		}

		/**
			`d` with an edge modifier `m` at the centre `cx` of the edge at `baseY`,
			`dir` 1 on the top edge and -1 on the bottom, so the body lies the way
			`dir` points: a scoop carved in with rounded ears, a bulge's arc
			added, a V cut in, or a V peak added. What is added reaches `into`
			past the edge into the body, no wider there than at the edge, so no
			seam shows inside.
		**/
		function notchEdge(p : Vec2, d : Float, cx : Float, baseY : Float, m : Vec4, dir : Float, into : Float) : Float {
			var result = d;
			var w = m.y;
			var h = m.z;
			if (m.x > 0.5 && w > 0.001 && h > 0.001) {
				var halfW = w * 0.5;
				// In the edge's frame: y grows into the body from the baseline.
				var q = vec2(p.x, (p.y - baseY) * dir);
				if (m.x < 1.5) {
					// Scoop: a rect from the baseline to a half-disk's centre, and the half-disk below it.
					var diskR = min(halfW, h);
					var diskY = h - diskR;
					var disk = max(length(q - vec2(cx, diskY)) - diskR, diskY - q.y);
					// The rect only when the scoop is deeper than half its width; a flat one would pull the edge down beside the bowl.
					var hollow = disk;
					if (diskY > 0.001)
						hollow = min(sdShapedRect(q, vec2(cx - halfW, 0.), vec2(w, diskY), vec4(0., 0., 0., 0.), vec4(1., 1., 1., 1.)), disk);
					result = smax(d, -hollow, max(m.w, 0.001));
				} else if (m.x < 2.5) {
					// Bulge: the cap of a disk through the edge's ends and its apex, out from the baseline.
					var rb = (halfW * halfW + h * h) / max(2. * h, 0.001);
					// Inside the body it is kept to its width at the edge; outside, a tall one's circle keeps its full width.
					var side = abs(q.x - cx) - halfW;
					if (q.y < 0.)
						side = -100000.;
					var cap = max(max(length(q - vec2(cx, rb - h)) - rb, q.y - into), side);
					result = smin(d, cap, max(m.w, 0.001));
				} else if (m.x < 3.5) {
					result = smax(d, -sdTriangle(q, vec2(cx - halfW, 0.), vec2(cx, h), vec2(cx + halfW, 0.)), 1.5);
				} else {
					// Its sides carried on past the edge, so the V reaches into the body.
					var spread = halfW * (h + into) / h;
					var peak = max(sdTriangle(q, vec2(cx - spread, into), vec2(cx, -h), vec2(cx + spread, into)), abs(q.x - cx) - halfW);
					result = smin(d, peak, 1.5);
				}
			}
			return result;
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
