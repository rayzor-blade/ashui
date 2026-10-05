package ashui.canvaskit;

/**
	`GroundGrid`'s shader: a square on the plane at the grid's height,
	centred under the eye and as wide as the grid fades over, so it has a
	depth meshes hide it by. Each pixel works out its lines from where it
	is on the plane, a pixel wide at any distance (by the coordinates'
	screen derivatives), minor and major, the X axis red and the Z axis
	blue, faded by distance from the eye, with the scene's shadows falling
	on it as darkness under the lines. It sees the scene through
	ashui's `Scene` module, and reads its own settings from `grid`: size,
	subdivisions, fade start and end; minor and major colours (sRGB, with
	alpha); height and whether it draws axes. Ported from Blinc's canvas
	kit grid, there a full-screen pass without depth.
**/
class GridShader implements hlwgpu.hxsl.Shader {
	static var SRC = {
		@:import ashui.shaders.Scene;
		@:import ashui.shaders.Shadows;

		var output : { position : Vec4, color : Vec4 };

		@param var shadowMap : Sampler2D;
		@param var scene : StorageBuffer<Vec4>;
		@param var grid : StorageBuffer<Vec4>;

		var world : Vec3;

		function vertex() {
			var c = vec2(-1., -1.);
			if (vertexID == 1 || vertexID == 4)
				c = vec2(1., -1.);
			if (vertexID == 2 || vertexID == 3)
				c = vec2(-1., 1.);
			if (vertexID == 5)
				c = vec2(1., 1.);
			var eye = cameraEye();
			var reach = grid[0].w;
			world = vec3(eye.x + c.x * reach, grid[3].x, eye.z + c.y * reach);
			output.position = worldToClip(vec4(world, 1.));
		}

		function lineCoverage(coord : Vec2) : Float {
			var deriv = max(fwidth(coord), vec2(0.000001, 0.000001));
			var g = abs(fract(coord - vec2(0.5, 0.5)) - vec2(0.5, 0.5));
			return 1. - min(min(g.x / deriv.x, g.y / deriv.y), 1.);
		}

		function fragment() {
			var spacing = grid[0];
			var hit = world.xz;
			var minorCoord = hit / (spacing.x / spacing.y);
			var minorDeriv = max(fwidth(minorCoord), vec2(0.000001, 0.000001));
			var minorAlpha = lineCoverage(minorCoord);
			var majorAlpha = lineCoverage(hit / spacing.x);
			var minor = grid[1];
			var major = grid[2];
			var color = minor.rgb;
			color = mix(color, major.rgb, majorAlpha);
			var alpha = max(minorAlpha * minor.a, majorAlpha * major.a);
			if (grid[3].y > 0.5) {
				var xAxis = smoothstep(minorDeriv.y, 0., abs(hit.y));
				var zAxis = smoothstep(minorDeriv.x, 0., abs(hit.x));
				color = mix(color, vec3(0.85, 0.25, 0.25), xAxis);
				color = mix(color, vec3(0.25, 0.4, 0.9), zAxis);
				alpha = max(alpha, max(xAxis, zAxis) * 0.85);
			}
			// Shadows fall on the ground as darkness, the lines over it.
			var shade = 1. - shadowLight(world);
			var cover = max(alpha, shade);
			var fade = 1. - smoothstep(spacing.z, spacing.w, length(hit - cameraEye().xz));
			if (cover * fade < 0.01)
				discard;
			output.color = vec4(color * (alpha / max(cover, 0.0001)), cover * fade);
		}
	};
}
