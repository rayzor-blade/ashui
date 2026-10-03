package ashui.core.render;

/** Copies `layer` texel for texel over the whole target, blending off: a frame drawn offscreen, onto the target. **/
class BlitShader implements UiShader {
	static var SRC = {
		@:import ashui.core.render.Sdf;

		@param var layer : Sampler2D;

		var output : { position : Vec4, color : Vec4 };

		function vertex() {
			output.position = pixelToClip(quadCorner(vertexID) * viewport, viewport);
		}

		function fragment() {
			output.color = layer.fetch(ivec2(int(fragCoord.x), int(fragCoord.y)));
		}
	};
}
