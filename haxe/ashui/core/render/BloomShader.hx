package ashui.core.render;

/**
	The steps of bloom, one full-screen pass each. `bloom[0]` holds the
	source's texel size, which step to run, and that step's value:

	- 0, threshold: halves the glow and keeps only what is brighter than
	  the value, with a soft knee so the cut is not abrupt. Each of its four
	  taps is weighted down by its own brightness, so that a single very
	  bright pixel does not flicker.
	- 1, down: halves the image again, with the dual Kawase filter.
	- 2, up: doubles the image and adds it onto the next larger level.
	- 3, add: adds the finished bloom onto the layer, scaled by the value.

	Run as a chain down to a few dozen pixels and back up, it spreads
	bright light widely without needing a wide blur kernel.
**/
class BloomShader implements hlwgpu.hxsl.Shader {
	static var SRC = {
		var output : { position : Vec4, color : Vec4 };

		@param var bloomSource : Sampler2D;
		@param var bloom : StorageBuffer<Vec4>;

		var uv : Vec2;

		function vertex() {
			// A triangle past the corners: (-1, -1), (3, -1), (-1, 3).
			var c = vec2(-1., -1.);
			if (vertexID == 1)
				c = vec2(3., -1.);
			if (vertexID == 2)
				c = vec2(-1., 3.);
			uv = vec2(c.x * 0.5 + 0.5, 0.5 - c.y * 0.5);
			output.position = vec4(c, 0., 1.);
		}

		function tap(at : Vec2) : Vec3 {
			return textureLod(bloomSource, at, 0.).rgb;
		}

		/** What of `c` passes `threshold`, eased in over a knee half its size. **/
		function bright(c : Vec3, threshold : Float) : Vec3 {
			var level = max(c.r, max(c.g, c.b));
			var knee = threshold * 0.5;
			var soft = clamp(level - threshold + knee, 0., 2. * knee);
			soft = soft * soft / (4. * knee + 0.00001);
			var kept = max(soft, level - threshold) / max(level, 0.00001);
			return c * kept;
		}

		function fragment() {
			var s = bloom[0];
			var t = s.xy;
			var step = s.z;
			var result = vec3(0., 0., 0.);
			if (step < 0.5) {
				var a = bright(tap(uv + t * vec2(-1., -1.)), s.w);
				var b = bright(tap(uv + t * vec2(1., -1.)), s.w);
				var c = bright(tap(uv + t * vec2(-1., 1.)), s.w);
				var d = bright(tap(uv + t * vec2(1., 1.)), s.w);
				var wa = 1. / (1. + max(a.r, max(a.g, a.b)));
				var wb = 1. / (1. + max(b.r, max(b.g, b.b)));
				var wc = 1. / (1. + max(c.r, max(c.g, c.b)));
				var wd = 1. / (1. + max(d.r, max(d.g, d.b)));
				result = (a * wa + b * wb + c * wc + d * wd) / (wa + wb + wc + wd);
			} else if (step < 1.5) {
				result = (tap(uv) * 4. + tap(uv + t * vec2(-1., -1.)) + tap(uv + t * vec2(1., -1.)) + tap(uv + t * vec2(-1., 1.))
					+ tap(uv + t * vec2(1., 1.))) / 8.;
			} else if (step < 2.5) {
				result = (tap(uv + t * vec2(-2., 0.)) + tap(uv + t * vec2(2., 0.)) + tap(uv + t * vec2(0., -2.)) + tap(uv + t * vec2(0., 2.))
					+ (tap(uv + t * vec2(-1., -1.)) + tap(uv + t * vec2(1., -1.)) + tap(uv + t * vec2(-1., 1.)) + tap(uv + t * vec2(1., 1.))) * 2.) / 12.;
			} else {
				result = tap(uv) * s.w;
			}
			output.color = vec4(result, 1.);
		}
	};
}
