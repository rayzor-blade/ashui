package ashui.core.render;

/**
	The finishing pass over a rendered 3D layer: a fish-eye lens and a
	vignette.

	The fish-eye makes each pixel read the layer from further out the
	further the pixel is from the centre, so the centre is magnified and
	the edges are compressed, while the corners stay at the corners. The
	vignette then darkens the image towards its edges and corners.

	`lens[0]` holds the fish-eye's strength, the layer's width divided by
	its height, the squared distance from the centre to a corner (measured
	in heights), and the vignette's strength.
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
			var c = textureLod(lensSource, vec2(q.x / s.y * 0.5 + 0.5, q.y * 0.5 + 0.5), 0.);
			// The vignette: full brightness in the middle, falling off smoothly towards the corners.
			var r = sqrt(dot(p, p) / s.z);
			var shade = 1. - s.w * smoothstep(0.35, 1.05, r);
			output.color = vec4(c.rgb * shade, c.a);
		}
	};
}
