package ashui.shaders;

/**
	What a 3D scene's shaders share, for `@:import ashui.shaders.Scene;`:
	the camera, the lights, the ambient light and the exposure, read from
	the `scene` buffer a canvas fills for each run of meshes (see
	`ashui.draw3d.Scene3D`). A shader drawn in a run binds the same buffer
	and reads it through these, so a grid, a sky or a material of one's
	own sees and lights the scene as the meshes do. As with any HXSL
	import, the functions come in and the parameter does not: the shader
	declares `@param var scene : StorageBuffer<Vec4>;` itself.

	The buffer is rows of four floats: the view-projection's columns, the
	eye and the light count, the ambient light and the exposure, the
	environment's intensity, its blurriest mip level and whether there is
	one, the shadow's light view-projection's columns, whether there are
	shadows with their bias, strength and map size, then four rows each
	light: its kind (0 directional, 1 point, 2 spot), range and
	spot cone's cosines; its colour times its intensity; its position; the
	way it shines. Colours are linear.
**/
class Scene implements #if ashui_caribou caribou.hxsl.Shader #else hlwgpu.hxsl.Shader #end {
	public static inline var MAX_LIGHTS = 8;
	public static inline var LIGHT_ROWS = 4;
	public static inline var FIRST_LIGHT = 12;
	public static inline var ROWS = FIRST_LIGHT + MAX_LIGHTS * LIGHT_ROWS;

	static var SRC = {
		@param var scene : StorageBuffer<Vec4>;

		/** A point in the scene, `w` 1, or a direction, `w` 0, to clip space through the camera. **/
		function worldToClip(p : Vec4) : Vec4 {
			return scene[0] * p.x + scene[1] * p.y + scene[2] * p.z + scene[3] * p.w;
		}

		/** Where the camera is. **/
		function cameraEye() : Vec3 {
			return scene[4].xyz;
		}

		/** The light that reaches everywhere, times its strength. **/
		function ambientLight() : Vec3 {
			return scene[5].rgb;
		}

		/** What lit colours are multiplied by before tone mapping. **/
		function sceneExposure() : Float {
			return scene[5].w;
		}

		/** What the environment's light is multiplied by. **/
		function environmentIntensity() : Float {
			return scene[6].x;
		}

		/** The environment's blurriest mip level, which rough surfaces and diffuse light sample. **/
		function environmentLevels() : Float {
			return scene[6].y;
		}

		/** Whether there is an environment; without one, ambient light stands in for it. **/
		function hasEnvironment() : Bool {
			return scene[6].z > 0.5;
		}

		/** A point in the scene, `w` 1, in the shadow-casting light's clip space. **/
		function worldToShadow(p : Vec4) : Vec4 {
			return scene[7] * p.x + scene[8] * p.y + scene[9] * p.z + scene[10] * p.w;
		}

		/** Whether there are shadows, their bias, strength and map size. **/
		function shadowSettings() : Vec4 {
			return scene[11];
		}

		function lightCount() : Int {
			return int(scene[4].w + 0.5);
		}

		/** The way from `at` toward light `i`, of unit length. **/
		function lightDirection(i : Int, at : Vec3) : Vec3 {
			var row = 12 + i * 4;
			var l = -normalize(scene[row + 3].xyz);
			if (scene[row].x > 0.5)
				l = normalize(scene[row + 2].xyz - at);
			return l;
		}

		/** The light `i` brings to `at`: its colour and intensity, faded by distance and, for a spot, its cone. **/
		function lightRadiance(i : Int, at : Vec3) : Vec3 {
			var row = 12 + i * 4;
			var kind = scene[row];
			var fade = 1.;
			if (kind.x > 0.5) {
				var toLight = scene[row + 2].xyz - at;
				var dist = max(length(toLight), 0.0001);
				var edge = clamp(1. - pow(dist / max(kind.y, 0.0001), 4.), 0., 1.);
				fade = edge * edge / max(dist * dist, 0.0001);
				if (kind.x > 1.5)
					fade *= smoothstep(kind.w, kind.z, dot(-toLight / dist, normalize(scene[row + 3].xyz)));
			}
			return scene[row + 1].rgb * fade;
		}
	};
}
