package ashui.core.render;

/**
	A fish-eye lens applied to a rendered 3D layer. Each pixel reads the
	layer from further out the further the pixel is from the centre, so the
	centre is magnified and the edges are compressed, while the corners
	stay at the corners.

	`lens[0]` holds the strength, the layer's width divided by its height,
	and the squared distance from the centre to a corner, measured in
	heights.
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
			output.color = textureLod(lensSource, vec2(q.x / s.y * 0.5 + 0.5, q.y * 0.5 + 0.5), 0.);
		}
	};
}
