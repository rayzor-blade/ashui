package ashui.core.render;

/**
	`MeshShadowShader` for masked and blended materials: a fragment casts
	only where the base colour's alpha reaches the material's cutoff, or a
	half for a blended one, so leaves cast leaf shapes and a shell an
	exporter marked blended casts as the solid it is.
**/
class MeshCutoutShadowShader implements hlwgpu.hxsl.Shader {
	static var SRC = {
		@:import ashui.shaders.Scene;
		@:import ashui.shaders.MeshDraw;

		@input var input : { position : Vec3, uv : Vec2 };
		var output : { position : Vec4, color : Vec4 };

		@param var baseColorMap : Sampler2D;
		@param var scene : StorageBuffer<Vec4>;
		@param var draws : StorageBuffer<Vec4>;

		var clip : Vec4;
		var texcoord : Vec2;
		var drawIndex : Int;

		function vertex() {
			clip = worldToShadow(modelToWorld(instanceID, vec4(input.position, 1.)));
			texcoord = input.uv;
			drawIndex = instanceID;
			output.position = clip;
		}

		function fragment() {
			var alpha = texture(baseColorMap, texcoord).a * drawBaseColor(drawIndex).a;
			var mode = drawFlags(drawIndex).z;
			var cutoff = 0.5;
			if (mode > 0.5 && mode < 1.5)
				cutoff = drawEmissive(drawIndex).w;
			if (alpha < cutoff)
				discard;
			output.color = vec4(clip.z / clip.w, 0., 0., 1.);
		}
	};
}
