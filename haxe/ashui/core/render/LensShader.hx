package ashui.core.render;

/**
	The finishing pass over a rendered 3D layer: a fish-eye lens, chromatic
	aberration, a vignette and film grain.

	The fish-eye makes each pixel read the layer from further out the
	further the pixel is from the centre, so the centre is magnified and
	the edges are compressed, while the corners stay at the corners.
	Chromatic aberration reads red slightly further out and blue slightly
	further in than green, more towards the edges, as a real lens splits
	colours. The vignette darkens the image towards its edges and corners,
	and film grain adds faint noise that changes every frame.

	`lens[0]` holds the fish-eye's strength, the layer's width divided by
	its height, the squared distance from the centre to a corner (measured
	in heights), and the vignette's strength. `lens[1]` holds the grain's
	strength, the aberration's strength, the time in seconds, and the
	layer's width in pixels.
**/
class LensShader implements hlwgpu.hxsl.Shader {
	static var SRC = {
		var output : { position : Vec4, color : Vec4 };

		@param var lensSource : Sampler2D;
		@param var lens : StorageBuffer<Vec4>;

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

		function fragment() {
			var s = lens[0];
			// Out from the middle in heights, so the bend is round whatever the shape.
			var p = vec2((uv.x * 2. - 1.) * s.y, uv.y * 2. - 1.);
			var q = p * (1. + s.x * dot(p, p)) / (1. + s.x * s.z);
			var e = lens[1];
			var r = sqrt(dot(p, p) / s.z);
			// Chromatic aberration: red read a little further out, blue a little further in, growing with the distance from the centre.
			var split = q * (e.y * 0.012 * r * r);
			var at = vec2(q.x / s.y * 0.5 + 0.5, q.y * 0.5 + 0.5);
			var shift = vec2(split.x / s.y * 0.5, split.y * 0.5);
			var c = textureLod(lensSource, at, 0.);
			var red = textureLod(lensSource, at + shift, 0.).r;
			var blue = textureLod(lensSource, at - shift, 0.).b;
			var rgb = vec3(red, c.g, blue);
			// The vignette: full brightness in the middle, falling off smoothly towards the corners.
			rgb *= 1. - s.w * smoothstep(0.35, 1.05, r);
			// Film grain: per-pixel noise, new each frame, strongest in the mid-tones as film's is.
			var pixel = floor(uv * vec2(e.w, e.w / s.y));
			var noise = fract(sin(dot(pixel + vec2(fract(e.z * 7.13) * 931., fract(e.z * 3.71) * 577.), vec2(12.9898, 78.233))) * 43758.5453);
			var mid = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
			rgb += vec3(noise - 0.5, noise - 0.5, noise - 0.5) * e.x * 0.08 * (0.35 + mid * (1. - mid) * 2.6);
			output.color = vec4(rgb, c.a);
		}
	};
}
