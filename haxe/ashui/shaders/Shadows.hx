package ashui.shaders;

/**
	Shadows, for `@:import ashui.shaders.Shadows;`: how lit a point is by
	the shadow-casting light (`shadowLight`), from the scene's shadow map,
	and the depth a shadow pass writes (`shadowDepth`). The map holds each
	pixel's depth from the light, 0 to 1, in its red; a point further than
	what is stored there is in shadow. `groundShadow` is how much a shadow
	darkens a floor that catches it. A shader that imports this declares
	`@param var shadowMap : Sampler2D;` and `environmentMap : SamplerCube`
	beside `scene`, and imports `Scene` too.
**/
class Shadows implements #if ashui_caribou caribou.hxsl.Shader #else hlwgpu.hxsl.Shader #end {
	static var SRC = {
		@:import ashui.shaders.Scene;

		// Declared for this module's own build; a shader importing it declares them itself.
		@param var shadowMap : Sampler2D;
		@param var environmentMap : SamplerCube;
		@param var scene : StorageBuffer<Vec4>;

		/** 1 where `world` is lit by the first light, down to 1 less the shadows' strength where it is in shadow; nine texels averaged, so edges are soft. **/
		function shadowLight(world : Vec3) : Float {
			var settings = shadowSettings();
			var lit = 1.;
			if (settings.x > 0.5) {
				var p = worldToShadow(vec4(world, 1.));
				var ndc = p.xyz / p.w;
				var uv = vec2(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
				if (uv.x > 0. && uv.x < 1. && uv.y > 0. && uv.y < 1. && ndc.z < 1.) {
					var size = settings.w;
					var at = uv * size;
					var seen = 0.;
					var dy = -1;
					while (dy <= 1) {
						var dx = -1;
						while (dx <= 1) {
							// At the texel's centre, where filtering gives the texel itself: a sampled read keeps the sampler bound.
							var t = (floor(at) + vec2(float(dx), float(dy)) + vec2(0.5, 0.5)) / size;
							if (ndc.z - settings.y <= textureLod(shadowMap, t, 0.).r)
								seen += 1.;
							dx++;
						}
						dy++;
					}
					lit = mix(1., seen / 9., settings.z);
				}
			}
			return lit;
		}

		/** The share of the light reaching level ground at `at` that the first light gives, weighed as ashui's mesh shader weighs it. **/
		function keyLightShare(at : Vec3) : Float {
			var up = vec3(0., 1., 0.);
			var luma = vec3(0.2126, 0.7152, 0.0722);
			var key = 0.;
			var rest = 0.;
			var count = lightCount();
			var i = 0;
			while (i < 8) {
				if (i < count) {
					var falling = dot(lightRadiance(i, at), luma) * max(dot(up, lightDirection(i, at)), 0.) / 3.14159265;
					if (i == 0)
						key = falling;
					else
						rest += falling;
				}
				i++;
			}
			if (hasEnvironment())
				rest += dot(textureLod(environmentMap, up, environmentLevels()).rgb * environmentIntensity(), luma);
			else
				rest += dot(ambientLight() * 1.1, luma);
			return key / max(key + rest, 0.0001);
		}

		/**
			How much darker level ground at `at` is for the first light's shadow
			there, 0 to 1: as dark as the light the shadow keeps off is strong
			against the rest, so a sky or a second light lifts it. A floor that
			catches shadows multiplies its colour by one less this.
		**/
		function groundShadow(at : Vec3) : Float {
			return (1. - shadowLight(at)) * keyLightShare(at);
		}

		/** What a shadow pass writes for a point at `clip` in the light's clip space: its depth. **/
		function shadowDepth(clip : Vec4) : Vec4 {
			return vec4(clip.z / clip.w, 0., 0., 1.);
		}
	};
}
