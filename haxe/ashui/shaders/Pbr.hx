package ashui.shaders;

/**
	Physically based shading, for `@:import ashui.shaders.Pbr;`: how a
	surface of a base colour, metallic and rough as glTF has them, reflects
	light from one direction (`directLight`) and from all around
	(`environmentBrdf`). Highlights spread as GGX has them, shadowed by
	Smith's term with Schlick's fit, brightening at grazing angles by
	Schlick's Fresnel. Vectors are unit length; colours linear.
**/
class Pbr implements #if ashui_caribou caribou.hxsl.Shader #else hlwgpu.hxsl.Shader #end {
	static var SRC = {
		/** How many microfacets face halfway between the light and the eye. **/
		function distributionGGX(nh : Float, roughness : Float) : Float {
			var a = roughness * roughness;
			var a2 = a * a;
			var k = nh * nh * (a2 - 1.) + 1.;
			return a2 / max(3.14159265 * k * k, 0.0000001);
		}

		/** How much of a surface is not shadowed by its own microfacets, one way. **/
		function geometrySchlick(nx : Float, roughness : Float) : Float {
			var r = roughness + 1.;
			var k = r * r / 8.;
			return nx / (nx * (1. - k) + k);
		}

		/** How much is reflected rather than let in, at an angle with cosine `cosTheta`. **/
		function fresnel(cosTheta : Float, f0 : Vec3) : Vec3 {
			return f0 + (vec3(1., 1., 1.) - f0) * pow(clamp(1. - cosTheta, 0., 1.), 5.);
		}

		/** The colour reflected head-on: 4% for anything but metal, the base colour for metal. **/
		function reflectance(albedo : Vec3, metallic : Float) : Vec3 {
			return mix(vec3(0.04, 0.04, 0.04), albedo, metallic);
		}

		/** What reaches the eye along `v` of `radiance` arriving along `l`, at a surface facing `n`. **/
		function directLight(n : Vec3, v : Vec3, l : Vec3, radiance : Vec3, albedo : Vec3, metallic : Float, roughness : Float) : Vec3 {
			var nl = max(dot(n, l), 0.);
			var nv = max(dot(n, v), 0.0001);
			var h = normalize(v + l);
			var f = fresnel(max(dot(h, v), 0.), reflectance(albedo, metallic));
			var spec = f * (distributionGGX(max(dot(n, h), 0.), roughness) * geometrySchlick(nv, roughness) * geometrySchlick(nl, roughness)
				/ max(4. * nv * nl, 0.0001));
			var kd = (vec3(1., 1., 1.) - f) * (1. - metallic);
			return (kd * albedo / 3.14159265 + spec) * radiance * nl;
		}

		/** How much of the environment a surface reflects toward the eye, by Karis' fit of the split-sum BRDF. **/
		function environmentBrdf(f0 : Vec3, roughness : Float, nv : Float) : Vec3 {
			var r = vec4(-1., -0.0275, -0.572, 0.022) * roughness + vec4(1., 0.0425, 1.04, -0.04);
			var a004 = min(r.x * r.x, exp2(-9.28 * nv)) * r.x + r.y;
			var ab = vec2(-1.04, 1.04) * a004 + r.zw;
			return f0 * ab.x + vec3(ab.y, ab.y, ab.y);
		}
	};
}
