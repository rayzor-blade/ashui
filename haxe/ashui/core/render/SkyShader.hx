package ashui.core.render;

/**
	A scene's skybox behind its meshes: one triangle over the whole layer,
	each pixel the sky seen through it from the eye, an environment at the
	skybox's mip level or a gradient by height, exposed and tone-mapped as
	the meshes are.
**/
class SkyShader implements hlwgpu.hxsl.Shader {
	static var SRC = {
		@:import ashui.shaders.Scene;
		@:import ashui.shaders.ColorSpace;

		var output : { position : Vec4, color : Vec4 };

		@param var environmentMap : SamplerCube;
		@param var scene : StorageBuffer<Vec4>;

		var ndc : Vec2;

		function vertex() {
			// A triangle past the corners: (-1, -1), (3, -1), (-1, 3).
			var c = vec2(-1., -1.);
			if (vertexID == 1)
				c = vec2(3., -1.);
			if (vertexID == 2)
				c = vec2(-1., 3.);
			ndc = c;
			output.position = vec4(c, 1., 1.);
		}

		function fragment() {
			var d = viewDirection(ndc);
			var sky = skyboxGradient(d);
			if (skyboxKind() < 1.5)
				sky = textureLod(environmentMap, d, skyboxLevel()).rgb;
			sky *= skyboxIntensity();
			output.color = vec4(linearToSrgb(toneMapAces(sky * sceneExposure())), 1.);
		}
	};
}
