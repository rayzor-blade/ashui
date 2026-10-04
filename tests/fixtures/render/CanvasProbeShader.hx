/**
	A canvas client drawing red over a quad larger than its canvas, so that
	only the clips bound what it covers: the scissor, and `canvasClip`.
**/
class CanvasProbeShader implements ashui.core.render.UiShader {
	static var SRC = {
		@:import ashui.core.render.Sdf;

		var output : { position : Vec4, color : Vec4 };
		var pixel : Vec2;

		function vertex() {
			var b = primitive.bounds;
			var uv = quadCorner(vertexID) * 1.6 - vec2(0.3, 0.3);
			pixel = placed(b.xy, primitive.affine, uv * b.zw);
			output.position = pixelToClip(pixel, viewport);
		}

		function fragment() {
			output.color = vec4(1., 0., 0., canvasClip(pixel));
		}
	};
}
