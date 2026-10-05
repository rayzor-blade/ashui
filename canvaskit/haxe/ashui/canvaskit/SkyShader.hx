package ashui.canvaskit;

/**
	`SkyboxPass`'s shader: one triangle over the whole layer, each pixel
	the sky seen through it from the eye, an environment at the skybox's
	mip level or a gradient by height, exposed and tone-mapped as the
	meshes are. Its own settings are in `sky`: the inverse view-projection's
	columns, the eye, the kind (1 a sky, 2 a gradient), mip level,
	intensity and whether it is grounded, the gradient's zenith, horizon
	and ground (linear), then a grounded sky's floor, height and radius; a
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
			var p = sky[0] * ndc.x + sky[1] * ndc.y + sky[2] + sky[3];
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
			c *= sky[5].z * (1. - shade);
			output.color = vec4(linearToSrgb(toneMapAces(c * sceneExposure())), 1.);
		}
	};
}
