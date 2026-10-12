package ashui.canvaskit;

/** Selected mesh silhouettes and creases, with depth and a constant screen width. 8ceba8d. **/
class SelectionEdgeShader implements hlwgpu.hxsl.Shader {
	static var SRC = {
		@:import ashui.shaders.Scene;
		var output : { position : Vec4, color : Vec4 };
		@param var scene : StorageBuffer<Vec4>;
		@param var edges : StorageBuffer<Vec4>;
		@param var settings : StorageBuffer<Vec4>;
		var across : Float;

		function placed(p : Vec3) : Vec3 {
			return (settings[0] * p.x + settings[1] * p.y + settings[2] * p.z + settings[3]).xyz;
		}

		function normal(n : Vec3) : Vec3 {
			return normalize((settings[4] * n.x + settings[5] * n.y + settings[6] * n.z).xyz);
		}

		function vertex() {
			var i = instanceID * 4;
			var a = placed(edges[i].xyz), b = placed(edges[i + 1].xyz);
			var n0 = edges[i + 2], n1 = edges[i + 3];
			var look = cameraEye() - (a + b) * 0.5;
			var front0 = dot(normal(n0.xyz), look) > 0.;
			var front1 = dot(normal(n1.xyz), look) > 0.;
			var visible = (front0 || front1) && (n0.w > 0.5 || front0 != front1);
			var ca = worldToClip(vec4(a, 1.)), cb = worldToClip(vec4(b, 1.));
			// Clip to the near plane before division, including edges crossing behind the eye.
			if (ca.z < 0. && cb.z >= 0.) ca = mix(ca, cb, -ca.z / (cb.z - ca.z));
			if (cb.z < 0. && ca.z >= 0.) cb = mix(cb, ca, -cb.z / (ca.z - cb.z));
			var viewport = settings[7];
			var delta = (cb.xy / max(cb.w, 0.00001) - ca.xy / max(ca.w, 0.00001)) * viewport.xy;
			var perpendicular = vec2(-delta.y, delta.x) / max(length(delta), 0.00001);
			var end = vertexID == 1 || vertexID == 4 || vertexID == 5;
			var side = vertexID == 2 || vertexID == 3 || vertexID == 5 ? 1. : -1.;
			var clip = end ? cb : ca;
			across = side * (viewport.z + 0.75);
			var offset = perpendicular * across * 2. / viewport.xy * clip.w;
			clip = vec4(clip.xy + offset, clip.zw);
			// Just in front of its own surface; other meshes still hide it.
			clip.z -= 0.000002 * clip.w;
			output.position = visible && ca.z >= 0. && cb.z >= 0. && ca.w > 0. && cb.w > 0. ? clip : vec4(2., 2., 2., 1.);
		}

		function fragment() {
			var cover = 1. - smoothstep(settings[7].z - 0.5, settings[7].z + 0.75, abs(across));
			output.color = vec4(settings[8].rgb, cover * settings[8].a);
		}
	};
}
