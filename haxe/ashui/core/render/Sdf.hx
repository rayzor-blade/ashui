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

		/** How much of the pixel at `p` a clip leaves; `clipType` 0 is none, 1 a rounded rect. **/
		function clipCoverage(p : Vec2, bounds : Vec4, radii : Vec4, clipType : Float) : Float {
			var alpha = 1.;
			if (clipType > 0.5)
				alpha = 1. - smoothstep(-0.75, 0.75, sdRoundedRect(p, bounds.xy, bounds.zw, radii));
			return alpha;
		}
	};
}
