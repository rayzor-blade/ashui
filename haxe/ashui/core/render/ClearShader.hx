package ashui.core.render;

/**
	Fills the target, blending off, with the one texel of `layer`: where a frame drawn offscreen is drawn again in part, the
	part is taken back to the window's colour first, which a clear load op cannot do under a scissor.
**/
class ClearShader implements UiShader {
	static var SRC = {
		@:import ashui.core.render.Sdf;
		@param var layer:Sampler2D;
		var output:{position:Vec4, color:Vec4};
		function vertex() {
			output.position = pixelToClip(quadCorner(vertexID) * viewport, viewport);
		}
		function fragment() {
			output.color = layer.fetch(ivec2(0, 0));
		}
	};
}
