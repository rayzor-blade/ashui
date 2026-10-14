package ashui.shaders;

/** Shared display-space selection mask for SceneKit and custom scene passes (git-bug 8d44ccf). */
class Selection implements #if ashui_caribou caribou.hxsl.Shader #else hlwgpu.hxsl.Shader #end {
	static var SRC = {
		function selectionMask(color:Vec3, normal:Vec3, toEye:Vec3):Vec3 {
			var luminance = dot(color, vec3(0.2126, 0.7152, 0.0722));
			var masked = vec3(0.10, 0.14, 0.20) + vec3(luminance * 0.20);
			var rim = pow(1. - abs(dot(normalize(normal), toEye)), 4.);
			return mix(mix(masked, color, 0.06), vec3(0.74, 0.88, 1.), rim * 0.12);
		}
	};
}
