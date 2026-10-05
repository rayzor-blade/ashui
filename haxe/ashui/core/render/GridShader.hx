package ashui.core.render;

/**
	A scene's ground grid: a square on the plane at the grid's height,
	centred under the eye and as wide as the grid fades over, so it has a
	depth meshes hide it by. Each pixel works out its lines from where it
	is on the plane, a pixel wide at any distance (by the coordinates'
	screen derivatives), minor and major, the X axis red and the Z axis
	blue, faded by distance from the eye. Ported from Blinc's canvas kit
	grid, there a full-screen pass without depth.
**/
class GridShader implements hlwgpu.hxsl.Shader {
	static var SRC = {
		@:import ashui.shaders.Scene;

		var output : { position : Vec4, color : Vec4 };

		@param var scene : StorageBuffer<Vec4>;

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
			var reach = gridSpacing().w;
			world = vec3(eye.x + c.x * reach, gridPlace().x, eye.z + c.y * reach);
			output.position = worldToClip(vec4(world, 1.));
		}

		function lineCoverage(coord : Vec2) : Float {
			var deriv = max(fwidth(coord), vec2(0.000001, 0.000001));
			var g = abs(fract(coord - vec2(0.5, 0.5)) - vec2(0.5, 0.5));
			return 1. - min(min(g.x / deriv.x, g.y / deriv.y), 1.);
		}

		function fragment() {
			var spacing = gridSpacing();
			var hit = world.xz;
			var minorCoord = hit / (spacing.x / spacing.y);
			var minorDeriv = max(fwidth(minorCoord), vec2(0.000001, 0.000001));
			var minorAlpha = lineCoverage(minorCoord);
			var majorAlpha = lineCoverage(hit / spacing.x);
			var minor = gridMinor();
			var major = gridMajor();
			var color = minor.rgb;
			color = mix(color, major.rgb, majorAlpha);
			var alpha = max(minorAlpha * minor.a, majorAlpha * major.a);
			if (gridPlace().y > 0.5) {
				var xAxis = smoothstep(minorDeriv.y, 0., abs(hit.y));
				var zAxis = smoothstep(minorDeriv.x, 0., abs(hit.x));
				color = mix(color, vec3(0.85, 0.25, 0.25), xAxis);
				color = mix(color, vec3(0.25, 0.4, 0.9), zAxis);
				alpha = max(alpha, max(xAxis, zAxis) * 0.85);
			}
			alpha *= 1. - smoothstep(spacing.z, spacing.w, length(hit - cameraEye().xz));
			if (alpha < 0.01)
				discard;
			output.color = vec4(color, alpha);
		}
	};
}
