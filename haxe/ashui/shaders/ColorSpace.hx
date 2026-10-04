package ashui.shaders;

/**
	Colour conversions, for `@:import ashui.shaders.ColorSpace;`. Lighting
	adds linear light; screens and `Brush` colours are sRGB; a lit colour
	brighter than 1 is brought into range by tone mapping before it is
	shown.
**/
class ColorSpace implements #if ashui_caribou caribou.hxsl.Shader #else hlwgpu.hxsl.Shader #end {
	static var SRC = {
		/** Linear light to the 0..1 range, by Narkowicz's fit of the ACES film curve. **/
		function toneMapAces(x : Vec3) : Vec3 {
			return clamp((x * (x * 2.51 + vec3(0.03, 0.03, 0.03))) / (x * (x * 2.43 + vec3(0.59, 0.59, 0.59)) + vec3(0.14, 0.14, 0.14)),
				vec3(0., 0., 0.), vec3(1., 1., 1.));
		}

		/** Linear 0..1 to sRGB, as a screen shows it. **/
		function linearToSrgb(c : Vec3) : Vec3 {
			var lo = c * 12.92;
			var hi = pow(max(c, vec3(0., 0., 0.)), vec3(1. / 2.4, 1. / 2.4, 1. / 2.4)) * 1.055 - vec3(0.055, 0.055, 0.055);
			return mix(lo, hi, step(vec3(0.0031308, 0.0031308, 0.0031308), c));
		}

		/** sRGB to linear. **/
		function srgbToLinear(c : Vec3) : Vec3 {
			var lo = c / 12.92;
			var hi = pow((c + vec3(0.055, 0.055, 0.055)) / 1.055, vec3(2.4, 2.4, 2.4));
			return mix(lo, hi, step(vec3(0.04045, 0.04045, 0.04045), c));
		}
	};
}
