package ashui.core.render;

/** A pixel surface quad in canvas coordinates, using the framework's transforms, clips and opacity. **/
class SurfaceShader implements UiShader {
	static var SRC = {
		@:import ashui.core.render.Sdf;
		@param var canvasSurface:Sampler2D;
		@param var canvasSurfaceInfo:Sampler2D;
		var output:{position:Vec4, color:Vec4};
		var pixel:Vec2;
		var uv:Vec2;
		function vertex() {
			var corner = quadCorner(vertexID);
			var rect = canvasSurfaceInfo.fetch(ivec2(0, 0));
			var crop = canvasSurfaceInfo.fetch(ivec2(1, 0));
			pixel = placed(primitive.bounds.xy, primitive.affine, rect.xy + corner * rect.zw);
			uv = crop.xy + corner * crop.zw;
			output.position = pixelToClip(pixel, viewport);
		}
		function fragment() {
			var texel = textureLod(canvasSurface, uv, 0.);
			var flags = canvasSurfaceInfo.fetch(ivec2(2, 0));
			var alpha = flags.x > 0.5 ? 1. : texel.a;
			output.color = vec4(texel.rgb, alpha * canvasClip(pixel));
		}
	};
}
