package ashui.core.render;

/**
	Meshes in 3D, shaded as glTF's metallic-roughness materials are: a
	base colour, metallic and roughness, normal, emissive and occlusion
	textures, lit by the scene's lights and by ambient light from a sky
	above and ground below, then exposed, tone-mapped and written as sRGB.
	Built from `ashui.shaders`: `Scene` for the camera and lights,
	`MeshDraw` for each draw's transform and material, `Pbr` and
	`ColorSpace`.
**/
class MeshShader implements hlwgpu.hxsl.Shader {
	static var SRC = {
		@:import ashui.shaders.Scene;
		@:import ashui.shaders.MeshDraw;
		@:import ashui.shaders.Pbr;
		@:import ashui.shaders.ColorSpace;

		@input var input : { position : Vec3, normal : Vec3, uv : Vec2, tangent : Vec4 };
		var output : { position : Vec4, color : Vec4 };

		@param var baseColorMap : Sampler2D;
		@param var normalMap : Sampler2D;
		@param var metalRoughMap : Sampler2D;
		@param var emissiveMap : Sampler2D;
		@param var occlusionMap : Sampler2D;
		@param var environmentMap : SamplerCube;
		@param var scene : StorageBuffer<Vec4>;
		@param var draws : StorageBuffer<Vec4>;

		var worldPos : Vec3;
		var worldNormal : Vec3;
		var worldTangent : Vec4;
		var texcoord : Vec2;
		var drawIndex : Int;

		function vertex() {
			var w = modelToWorld(instanceID, vec4(input.position, 1.));
			worldPos = w.xyz;
			worldNormal = normalToWorld(instanceID, input.normal);
			worldTangent = vec4(modelToWorld(instanceID, vec4(input.tangent.xyz, 0.)).xyz, input.tangent.w);
			texcoord = input.uv;
			drawIndex = instanceID;
			output.position = worldToClip(w);
		}

		function fragment() {
			var surface = drawSurface(drawIndex);
			var em = drawEmissive(drawIndex);
			var flags = drawFlags(drawIndex);
			var albedo = texture(baseColorMap, texcoord) * drawBaseColor(drawIndex);
			var alpha = albedo.a;
			if (flags.z > 0.5 && flags.z < 1.5) {
				if (alpha < em.w)
					discard;
				alpha = 1.;
			}
			if (flags.z < 0.5)
				alpha = 1.;
			var color = albedo.rgb;
			if (flags.y < 0.5) {
				var mr = texture(metalRoughMap, texcoord);
				var metallic = clamp(surface.x * mr.b, 0., 1.);
				var roughness = clamp(surface.y * mr.g, 0.04, 1.);
				var n = normalize(worldNormal);
				if (!frontFacing)
					n = -n;
				if (flags.x > 0.5) {
					// x and y from the texture; z worked out from them, as a two-channel (BC5) normal map stores none.
					var nxy = texture(normalMap, texcoord).xy * 2. - vec2(1., 1.);
					var tn = vec3(nxy * surface.z, sqrt(max(1. - dot(nxy, nxy), 0.)));
					var t = worldTangent.xyz - n * dot(n, worldTangent.xyz);
					if (dot(t, t) > 0.00000001) {
						t = normalize(t);
						var b = cross(n, t) * worldTangent.w;
						n = normalize(t * tn.x + b * tn.y + n * tn.z);
					}
				}
				var v = normalize(cameraEye() - worldPos);
				var lit = vec3(0., 0., 0.);
				var count = lightCount();
				var i = 0;
				while (i < 8) {
					if (i < count)
						lit += directLight(n, v, lightDirection(i, worldPos), lightRadiance(i, worldPos), albedo.rgb, metallic, roughness);
					i++;
				}
				var r = reflect(-v, n);
				var sky = vec3(0., 0., 0.);
				var around = vec3(0., 0., 0.);
				if (hasEnvironment()) {
					// The environment, blurred for the roughness along the reflection, and at its blurriest round the normal.
					var levels = environmentLevels();
					sky = textureLod(environmentMap, r, roughness * levels).rgb * environmentIntensity();
					around = textureLod(environmentMap, n, levels).rgb * environmentIntensity();
				} else {
					// Ambient: brighter from the sky than the ground.
					var ambient = ambientLight();
					sky = ambient * mix(0.35, 1.25, clamp(r.y * 0.5 + 0.5, 0., 1.));
					around = ambient * mix(0.6, 1.1, clamp(n.y * 0.5 + 0.5, 0., 1.));
				}
				var occlusion = mix(1., texture(occlusionMap, texcoord).r, surface.w);
				var f0 = reflectance(albedo.rgb, metallic);
				lit += (around * albedo.rgb * (1. - metallic) + sky * environmentBrdf(f0, roughness, max(dot(n, v), 0.0001))) * occlusion;
				lit += em.rgb * texture(emissiveMap, texcoord).rgb;
				color = toneMapAces(lit * sceneExposure());
			}
			output.color = vec4(linearToSrgb(color), alpha * flags.w);
		}
	};
}
