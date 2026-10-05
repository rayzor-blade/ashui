package ashui.core.render;

/**
	Meshes' depth from the shadow-casting light, for the scene's shadow
	map: each vertex placed as `MeshShader` places it, through the light's
	view-projection, its depth written to the map's red.
**/
class MeshShadowShader implements hlwgpu.hxsl.Shader {
	static var SRC = {
		@:import ashui.shaders.Scene;
		@:import ashui.shaders.MeshDraw;

		@input var input : { position : Vec3 };
		var output : { position : Vec4, color : Vec4 };

		@param var scene : StorageBuffer<Vec4>;
		@param var draws : StorageBuffer<Vec4>;

		var clip : Vec4;

		function vertex() {
			clip = worldToShadow(modelToWorld(instanceID, vec4(input.position, 1.)));
			output.position = clip;
		}

		function fragment() {
			output.color = vec4(clip.z / clip.w, 0., 0., 1.);
		}
	};
}
