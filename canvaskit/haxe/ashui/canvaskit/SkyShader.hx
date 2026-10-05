package ashui.canvaskit;

/**
	`SkyboxPass`'s shader: one triangle over the whole layer, each pixel
	the sky seen through it from the eye, an environment at the skybox's
	mip level or a gradient by height, exposed and tone-mapped as the
	meshes are. Its own settings are in `sky`: the inverse view-projection's
	columns, the eye, the kind (1 a sky, 2 a gradient), mip level,
	intensity and whether it is grounded (the kind 3 a panorama), the gradient's zenith, horizon
	and ground (linear), then a grounded sky's floor, height and radius,
	or a panorama's spread, whether it is upside down, its texels a radian
	and its turn as a share of the way round, then its sphere's centre and
	radius (0 for infinitely far), and whether it is drawing for bloom's
	glow pass; a
	grounded sky's floor darkens under the scene's shadows.
**/
class SkyShader implements hlwgpu.hxsl.Shader {
	static var SRC = {
		@:import ashui.shaders.Scene;
		@:import ashui.shaders.ColorSpace;
		@:import ashui.shaders.Shadows;

		var output : { position : Vec4, color : Vec4 };

		@param var environmentMap : SamplerCube;
		@param var shadowMap : Sampler2D;
		@param var panorama : Sampler2D;
		@param var scene : StorageBuffer<Vec4>;
		@param var sky : StorageBuffer<Vec4>;

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
			// A panorama's spread takes in more of the sky through each pixel, as a wider lens would.
			var spread = sky[5].x > 2.5 ? sky[9].x : 1.;
			var p = sky[0] * (ndc.x * spread) + sky[1] * (ndc.y * spread) + sky[2] + sky[3];
			var eye = sky[4].xyz;
			var d = normalize(p.xyz / p.w - eye);
			var shade = 0.;
			if (sky[5].w > 0.5) {
				// Grounded: seen from the sky's camera, `height` above the floor at the origin, a ray meets the floor
				// within `radius` of it, and beyond, the dome of that radius round the camera. The floor catches the shadows.
				var g = sky[9];
				var o = eye - vec3(0., g.x + g.y, 0.);
				var b = dot(o, d);
				var t = -b + sqrt(max(b * b - dot(o, o) + g.z * g.z, 0.));
				if (d.y < 0.) {
					var toFloor = (g.x - eye.y) / d.y;
					if (toFloor > 0. && toFloor < t) {
						t = toFloor;
						shade = groundShadow(eye + d * toFloor);
					}
				}
				d = normalize(o + d * t);
			}
			var c = mix(sky[7].rgb, sky[6].rgb, pow(clamp(d.y, 0., 1.), 0.6));
			if (d.y < 0.)
				c = mix(sky[7].rgb, sky[8].rgb, clamp(-d.y * 4., 0., 1.));
			if (sky[5].x < 1.5)
				c = textureLod(environmentMap, d, sky[5].y).rgb;
			// A panorama: its texel the way `d` looks, round by the way round (turned) and down from overhead, at full detail.
			var panoramic = sky[5].x > 2.5;
			if (panoramic) {
				// On a sphere of a radius round a centre, the eye within: the way to where the ray meets its far wall.
				var look = d;
				var dome = sky[10];
				if (dome.w > 0.) {
					var o = eye - dome.xyz;
					var b = dot(o, d);
					var disc = b * b - dot(o, o) + dome.w * dome.w;
					if (disc > 0.)
						look = normalize(o + d * (-b + sqrt(disc)));
				}
				// The mip level by how much sky the pixel covers: one texel a pixel at level 0, smaller levels as it takes in more.
				var lod = log2(max(1., length(fwidth(look)) * sky[9].z));
				var u = 0.5 + atan(look.x, -look.z) / 6.2831853 + sky[9].w;
				var v = acos(clamp(look.y, -1., 1.)) / 3.1415927;
				if (sky[9].y > 0.5)
					v = 1. - v;
				c = textureLod(panorama, vec2(fract(u), v), lod).rgb;
			}
			c *= sky[5].z * (1. - shade);
			// With fog, the sky at the horizon fades into it, so the ground's far edge meets the sky in the fog;
			// over a panorama the haze thins away up the sky, as air seen edge-on does, whole below the level.
			if (scene[6].w > 0.)
				c = mix(c, fogColor(), (panoramic ? exp(-max(d.y, 0.) * 9.) : 1. - smoothstep(0., 0.3, d.y)) * fogOpacity());
			// A panorama is shown as its picture is, its colours as they are; a sky or gradient is light, exposed and tone-mapped.
			var shown = linearToSrgb(toneMapAces(c * sceneExposure()));
			if (panoramic)
				shown = linearToSrgb(c);
			// In bloom's glow pass: the sky's light, linear and untone-mapped (a panorama's as it is shown).
			if (sky[11].x > 0.5)
				shown = panoramic ? c : c * sceneExposure();
			output.color = vec4(shown, 1.);
		}
	};
}
