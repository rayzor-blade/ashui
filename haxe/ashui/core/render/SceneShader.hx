package ashui.core.render;

/**
	A canvas's 3D layer over its box: `canvasLayer`, rendered at a multiple
	of the box's size on screen with premultiplied colour, filtered down
	as it is drawn, and clipped and faded as the canvas is.
**/
class SceneShader implements UiShader {
	static var SRC = {
		@:import ashui.core.render.Sdf;

		@param var canvasLayer : Sampler2D;

		var output : { position : Vec4, color : Vec4 };
		var pixel : Vec2;
		var uv : Vec2;

		function vertex() {
			var b = primitive.bounds;
			uv = quadCorner(vertexID);
			pixel = placed(b.xy, primitive.affine, uv * b.zw);
			output.position = pixelToClip(pixel, viewport);
		}

		function fragment() {
			var c = textureLod(canvasLayer, uv, 0.);
			var straight = c.a > 0.0001 ? c.rgb / c.a : vec3(0., 0., 0.);
			output.color = vec4(straight, c.a * canvasClip(pixel));
		}
	};
}
