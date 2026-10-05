package ashui.core.render;

/**
	Meshes in 3D, shaded as glTF's metallic-roughness materials are: a
	base colour, metallic and roughness, normal, emissive and occlusion
	textures, lit by the scene's lights, the first casting shadows from
	the scene's shadow map, and by the environment or ambient light, then
	exposed, tone-mapped and written as sRGB. In bloom's glow pass it writes
	the exposed light without tone mapping instead, so extensions glow too.
	Built from `ashui.shaders`: `Scene` for the camera and lights,
	`MeshDraw` for each draw's transform and material, `Pbr` and
	`ColorSpace`.

	It is four steps a shader can extend and replace, as a material of
	one's own does (`Material.shader`): `bend` moves where on screen each
	vertex is drawn, for example to curve ground away like a planet's or
	sway grass in the wind, while keeping its lighting; `surface` reads the material and
	its textures into `surfaceColor`, `surfaceMetallic`,
	`surfaceRoughness`, `surfaceNormal`, `surfaceEmission` and
	`surfaceOcclusion`; `shade` lights them, linear; `present` exposes,
	tone-maps and writes sRGB. A toon shader:

	```haxe
	class Toon implements hlwgpu.hxsl.Shader {
		static var SRC = {
			@:extends ashui.core.render.MeshShader;
			function shade() : Vec3 {
				var l = dot(surfaceNormal, lightDirection(0, worldPos));
				return surfaceColor.rgb * (l > 0.5 ? 1. : l > 0. ? 0.6 : 0.3);
			}
		};
	}
	new Material({baseColor: 0xe05030, shader: Toon.WGSL});
	```

	An extension keeps every parameter and binding as they are, so it adds
	none of its own; what needs its own data draws with a `ScenePass`.
**/
class MeshShader implements hlwgpu.hxsl.Shader {
	static var SRC = {
		@:import ashui.shaders.Scene;
		@:import ashui.shaders.MeshDraw;
		@:import ashui.shaders.Pbr;
		@:import ashui.shaders.ColorSpace;
		@:import ashui.shaders.Shadows;

		@input var input : { position : Vec3, normal : Vec3, uv : Vec2, tangent : Vec4 };
		var output : { position : Vec4, color : Vec4 };

		@param var baseColorMap : Sampler2D;
		@param var normalMap : Sampler2D;
		@param var metalRoughMap : Sampler2D;
		@param var emissiveMap : Sampler2D;
		@param var occlusionMap : Sampler2D;
		@param var environmentMap : SamplerCube;
		@param var shadowMap : Sampler2D;
		@param var scene : StorageBuffer<Vec4>;
		@param var draws : StorageBuffer<Vec4>;

		var worldPos : Vec3;
		var worldNormal : Vec3;
		var worldTangent : Vec4;
		var texcoord : Vec2;
		var drawIndex : Int;

		/** 1 when drawing for bloom's glow pass, 0 when drawing the scene. **/
		var glowPass : Float;

		/**
			Returns where a vertex placed at `world` is drawn on screen. By
			default that is `world` itself. Lighting, shadows and fog are still
			worked out at `world`, so a bent surface looks moved but is lit as
			if it had not moved.
		**/
		function bend(world : Vec3) : Vec3 {
			return world;
		}

		function vertex() {
			// The glow pass draws a mesh again with its instance index raised by the draw count.
			var draw = instanceID;
			glowPass = 0.;
			if (draw >= drawCount()) {
				draw = draw - drawCount();
				glowPass = 1.;
			}
			var w = modelToWorld(draw, vec4(input.position, 1.));
			worldPos = w.xyz;
			worldNormal = normalToWorld(draw, input.normal);
			worldTangent = vec4(modelToWorld(draw, vec4(input.tangent.xyz, 0.)).xyz, input.tangent.w);
			// Transformed here: the transform is affine, so it carries across the triangle as the coordinates do.
			texcoord = drawTexcoord(draw, input.uv);
			drawIndex = draw;
			output.position = worldToClip(vec4(bend(w.xyz), 1.));
		}

		// What `surface` reads and `shade` lights: linear colours.
		var surfaceColor : Vec4;
		var surfaceMetallic : Float;
		var surfaceRoughness : Float;
		var surfaceNormal : Vec3;
		var surfaceEmission : Vec3;
		var surfaceOcclusion : Float;
		var toEye : Vec3;

		/** The surface where this pixel is: its material's settings times its textures, its normal bent by its normal texture. **/
		function surface() {
			var settings = drawSurface(drawIndex);
			surfaceColor = texture(baseColorMap, texcoord) * drawBaseColor(drawIndex);
			var mr = texture(metalRoughMap, texcoord);
			surfaceMetallic = clamp(settings.x * mr.b, 0., 1.);
			surfaceRoughness = clamp(settings.y * mr.g, 0.04, 1.);
			var n = normalize(worldNormal);
			if (!frontFacing)
				n = -n;
			if (drawFlags(drawIndex).x > 0.5) {
				// x and y from the texture; z worked out from them, as a two-channel (BC5) normal map stores none.
				var nxy = texture(normalMap, texcoord).xy * 2. - vec2(1., 1.);
				var tn = vec3(nxy * settings.z, sqrt(max(1. - dot(nxy, nxy), 0.)));
				// A slope in the texture's coordinates is one in the mesh's through the texture transform's transpose:
				// turned that way, its steepness kept.
				var m = draws[drawIndex * 12 + 11];
				var turned = vec2(m.x * tn.x + m.z * tn.y, m.y * tn.x + m.w * tn.y);
				if (dot(turned, turned) > 0.00000001)
					tn = vec3(normalize(turned) * length(tn.xy), tn.z);
				var t = worldTangent.xyz - n * dot(n, worldTangent.xyz);
				if (dot(t, t) > 0.00000001) {
					t = normalize(t);
					var b = cross(n, t) * worldTangent.w;
					n = normalize(t * tn.x + b * tn.y + n * tn.z);
				}
			}
			surfaceNormal = n;
			surfaceEmission = drawEmissive(drawIndex).rgb * texture(emissiveMap, texcoord).rgb;
			surfaceOcclusion = mix(1., texture(occlusionMap, texcoord).r, settings.w);
			toEye = normalize(cameraEye() - worldPos);
		}

		/** The light the surface sends to the eye, linear: each light by `Pbr`, the environment or ambient light, its own glow. **/
		function shade() : Vec3 {
			var n = surfaceNormal;
			var v = toEye;
			var albedo = surfaceColor.rgb;
			var lit = vec3(0., 0., 0.);
			var count = lightCount();
			var i = 0;
			// The first light casts the shadows.
			var shadowed = shadowLight(worldPos);
			while (i < 8) {
				if (i < count)
					lit += directLight(n, v, lightDirection(i, worldPos), lightRadiance(i, worldPos) * (i == 0 ? shadowed : 1.), albedo, surfaceMetallic,
						surfaceRoughness);
				i++;
			}
			var r = reflect(-v, n);
			var sky = vec3(0., 0., 0.);
			var around = vec3(0., 0., 0.);
			if (hasEnvironment()) {
				// The environment, blurred for the roughness along the reflection, and at its blurriest round the normal.
				var levels = environmentLevels();
				sky = textureLod(environmentMap, r, surfaceRoughness * levels).rgb * environmentIntensity();
				around = textureLod(environmentMap, n, levels).rgb * environmentIntensity();
			} else {
				// Ambient: brighter from the sky than the ground.
				var ambient = ambientLight();
				sky = ambient * mix(0.35, 1.25, clamp(r.y * 0.5 + 0.5, 0., 1.));
				around = ambient * mix(0.6, 1.1, clamp(n.y * 0.5 + 0.5, 0., 1.));
			}
			var f0 = reflectance(albedo, surfaceMetallic);
			lit += (around * albedo * (1. - surfaceMetallic) + sky * environmentBrdf(f0, surfaceRoughness, max(dot(n, v), 0.0001))) * surfaceOcclusion;
			return lit + surfaceEmission;
		}

		/** Linear light as the screen shows it: exposed, tone-mapped, sRGB. **/
		function present(lit : Vec3) : Vec3 {
			return linearToSrgb(toneMapAces(lit * sceneExposure()));
		}

		/**
			Every texture and buffer it binds, read once: the compiler drops
			bindings a shader does not read and numbers the rest, so a shader
			extending this one that reads fewer would bind differently.
			`fragment` reads them where it never runs; an extension that
			replaces `fragment` calls it the same way.
		**/
		function everyBinding() : Vec4 {
			return texture(baseColorMap, texcoord) + texture(normalMap, texcoord) + texture(metalRoughMap, texcoord) + texture(emissiveMap, texcoord)
				+ texture(occlusionMap, texcoord) + textureLod(environmentMap, vec3(0., 1., 0.), 0.) + textureLod(shadowMap, texcoord, 0.) + scene[0] + draws[0];
		}

		function fragment() {
			surface();
			var flags = drawFlags(drawIndex);
			var alpha = surfaceColor.a;
			if (flags.z > 0.5 && flags.z < 1.5) {
				if (alpha < drawEmissive(drawIndex).w)
					discard;
				alpha = 1.;
			}
			// A blended material at full opacity is drawn twice: its solid fragments with the opaque meshes (3), then the rest (2).
			if (flags.z > 2.5) {
				if (alpha < 0.998)
					discard;
				alpha = 1.;
			} else if (flags.z > 1.5 && flags.w >= 1. && alpha >= 0.998)
				discard;
			if (flags.z < 0.5)
				alpha = 1.;
			// Faded into the fog before it is exposed and tone-mapped, as light through air would be.
			var unlit = flags.y > 0.5 ? (flags.y > 1.5 ? surfaceColor.rgb : applyFog(surfaceColor.rgb, worldPos)) : vec3(0., 0., 0.);
			var lit = flags.y > 0.5 ? unlit : applyFog(shade(), worldPos);
			var color = flags.y > 0.5 ? linearToSrgb(unlit) : present(lit);
			// For bloom's glow pass: the exposed light without tone mapping, so light brighter than white stays brighter.
			if (glowPass > 0.5) {
				color = lit * sceneExposure();
				alpha = 1.;
			}
			// Never true (opacity is not negative): it keeps every binding, for shaders extending this one.
			if (flags.w < -1.)
				color += everyBinding().rgb;
			output.color = vec4(color, glowPass > 0.5 ? 1. : alpha * flags.w);
		}
	};
}
