package dashboard;

/**
	The dashboard's car shaded a little as an illustration is, to sit with the
	flat panels round it. It lights the surface exactly as ashui's mesh
	shader does, then gathers the light into bands: its brightness is
	stepped, each step two thirds of a stop, with edges softened over a
	quarter of a step, and its hue kept; three quarters banded, a quarter
	as lit. So the paint's reflections of the
	studio's softbox and strip lights become crisp shapes, as a car is drawn,
	and the shading on trim and tyres falls in flat tones. Where the surface
	turns away from the eye it darkens to a soft line at the silhouette. The
	base colours and the texture are as the material gives them, and so is
	its glow. No part is rougher than the model makes it or smoother than
	satin, a roughness of 0.38.
**/
class CarToon implements hlwgpu.hxsl.Shader {
	static var SRC = {
		@:extends ashui.core.render.MeshShader;

		/** `lum` moved to its band: steps of two thirds of a stop, each edge softened. **/
		function band(lum:Float):Float {
			var t = log2(max(lum, 0.0001)) * 1.5 + 0.5;
			var whole = floor(t);
			var edge = smoothstep(0.76, 1.0, t - whole);
			return exp2((whole + edge - 0.5) / 1.5);
		}

		function shade():Vec3 {
			// The model's map makes its paint and glass a mirror; at this floor they read as satin paint and glass.
			surfaceRoughness = max(surfaceRoughness, 0.38);
			var n = surfaceNormal;
			var v = toEye;
			var albedo = surfaceColor.rgb;
			var lit = vec3(0., 0., 0.);
			var count = lightCount();
			var i = 0;
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
				var levels = environmentLevels();
				sky = textureLod(environmentMap, r, surfaceRoughness * levels).rgb * environmentIntensity();
				around = textureLod(environmentMap, n, levels).rgb * environmentIntensity();
			} else {
				var ambient = ambientLight();
				sky = ambient * mix(0.35, 1.25, clamp(r.y * 0.5 + 0.5, 0., 1.));
				around = ambient * mix(0.6, 1.1, clamp(n.y * 0.5 + 0.5, 0., 1.));
			}
			var f0 = reflectance(albedo, surfaceMetallic);
			lit += (around * albedo * (1. - surfaceMetallic) + sky * environmentBrdf(f0, surfaceRoughness, max(dot(n, v), 0.0001))) * surfaceOcclusion;
			var lum = dot(lit, vec3(0.2126, 0.7152, 0.0722));
			// Three quarters banded, a quarter as lit, so it reads as a touch of illustration rather than a cartoon.
			var banded = mix(lit, lit * (band(lum) / max(lum, 0.0001)), 0.75);
			// A soft line where the surface turns from the eye.
			banded *= mix(0.35, 1., smoothstep(0.06, 0.2, max(dot(n, v), 0.)));
			return banded + surfaceEmission;
		}
	};
}
