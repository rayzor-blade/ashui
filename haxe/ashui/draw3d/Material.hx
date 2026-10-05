package ashui.draw3d;

import ashui.types.Bitmap;

/** How a surface's alpha is used: ignored, as a cut-out at `alphaCutoff`, or blended over what is behind it. **/
enum abstract AlphaMode(Int) to Int {
	var Opaque = 0;
	var Mask = 1;
	var Blend = 2;
}

/** A material's settings, each optional; see `Material`. **/
typedef MaterialOptions = {
	?baseColor:Int,
	?alpha:Float,
	?metallic:Float,
	?roughness:Float,
	?emissive:Int,
	?emissiveStrength:Float,
	?baseColorTexture:Bitmap,
	?normalTexture:Bitmap,
	?normalScale:Float,
	?metallicRoughnessTexture:Bitmap,
	?emissiveTexture:Bitmap,
	?occlusionTexture:Bitmap,
	?occlusionStrength:Float,
	?alphaMode:AlphaMode,
	?alphaCutoff:Float,
	?unlit:Bool,
	?doubleSided:Bool,
	?shader:String,
	?textureTransform:TextureTransform,
	?fog:Bool,
	?culled:Bool,
}

/**
	What a surface is made of, as glTF describes it: a base colour, how
	metallic and how rough it is, light of its own, and textures for each.
	A texture multiplies its setting: `baseColorTexture` the base colour,
	the blue and green of `metallicRoughnessTexture` metallic and
	roughness, `emissiveTexture` the emissive colour; `occlusionTexture`'s
	red darkens the light that reaches into creases, and `normalTexture`
	bends the surface's normals for detail the triangles do not have.
	`textureTransform` scales, rotates and moves every texture on the
	surface, as glTF's `KHR_texture_transform` does. Setting `fog` to false
	keeps the surface out of the scene's fog, as a sky drawn as a mesh
	should be. A mesh is not drawn while its bounds are outside the camera's
	view; set `culled` to false for a material whose shader moves vertices
	far outside the mesh's own bounds. Colours are `0xRRGGBB`, as `Brush`
	takes them. `unlit` shows the base
	colour as it is, unshaded. `shader` is the WGSL of a shader that
	extends ashui's mesh shader (`@:extends ashui.core.render.MeshShader`)
	to light or present the surface its own way; ashui's own by default.
**/
class Material {
	public static final DEFAULT = new Material();

	public final baseColor:Int;
	public final alpha:Float;
	public final metallic:Float;
	public final roughness:Float;
	public final emissive:Int;
	public final emissiveStrength:Float;
	public final baseColorTexture:Null<Bitmap>;
	public final normalTexture:Null<Bitmap>;
	public final normalScale:Float;
	public final metallicRoughnessTexture:Null<Bitmap>;
	public final emissiveTexture:Null<Bitmap>;
	public final occlusionTexture:Null<Bitmap>;
	public final occlusionStrength:Float;
	public final alphaMode:AlphaMode;
	public final alphaCutoff:Float;
	public final unlit:Bool;
	public final doubleSided:Bool;
	public final shader:Null<String>;
	public final textureTransform:Null<TextureTransform>;
	public final fog:Bool;
	public final culled:Bool;

	public function new(?o:MaterialOptions) {
		if (o == null)
			o = {};
		baseColor = o.baseColor != null ? o.baseColor : 0xffffff;
		alpha = o.alpha != null ? o.alpha : 1;
		metallic = o.metallic != null ? o.metallic : 0;
		roughness = o.roughness != null ? o.roughness : 0.5;
		emissive = o.emissive != null ? o.emissive : 0x000000;
		emissiveStrength = o.emissiveStrength != null ? o.emissiveStrength : 1;
		baseColorTexture = o.baseColorTexture;
		normalTexture = o.normalTexture;
		normalScale = o.normalScale != null ? o.normalScale : 1;
		metallicRoughnessTexture = o.metallicRoughnessTexture;
		emissiveTexture = o.emissiveTexture;
		occlusionTexture = o.occlusionTexture;
		occlusionStrength = o.occlusionStrength != null ? o.occlusionStrength : 1;
		alphaMode = o.alphaMode != null ? o.alphaMode : Opaque;
		alphaCutoff = o.alphaCutoff != null ? o.alphaCutoff : 0.5;
		unlit = o.unlit == true;
		doubleSided = o.doubleSided == true;
		shader = o.shader;
		textureTransform = o.textureTransform;
		fog = o.fog != false;
		culled = o.culled != false;
	}

	/** A copy with the settings `o` gives in place of these. **/
	public function with(o:MaterialOptions):Material
		return new Material({
			baseColor: o.baseColor != null ? o.baseColor : baseColor,
			alpha: o.alpha != null ? o.alpha : alpha,
			metallic: o.metallic != null ? o.metallic : metallic,
			roughness: o.roughness != null ? o.roughness : roughness,
			emissive: o.emissive != null ? o.emissive : emissive,
			emissiveStrength: o.emissiveStrength != null ? o.emissiveStrength : emissiveStrength,
			baseColorTexture: o.baseColorTexture != null ? o.baseColorTexture : baseColorTexture,
			normalTexture: o.normalTexture != null ? o.normalTexture : normalTexture,
			normalScale: o.normalScale != null ? o.normalScale : normalScale,
			metallicRoughnessTexture: o.metallicRoughnessTexture != null ? o.metallicRoughnessTexture : metallicRoughnessTexture,
			emissiveTexture: o.emissiveTexture != null ? o.emissiveTexture : emissiveTexture,
			occlusionTexture: o.occlusionTexture != null ? o.occlusionTexture : occlusionTexture,
			occlusionStrength: o.occlusionStrength != null ? o.occlusionStrength : occlusionStrength,
			alphaMode: o.alphaMode != null ? o.alphaMode : alphaMode,
			alphaCutoff: o.alphaCutoff != null ? o.alphaCutoff : alphaCutoff,
			unlit: o.unlit != null ? o.unlit : unlit,
			doubleSided: o.doubleSided != null ? o.doubleSided : doubleSided,
			shader: o.shader != null ? o.shader : shader,
			textureTransform: o.textureTransform != null ? o.textureTransform : textureTransform,
			fog: o.fog != null ? o.fog : fog,
			culled: o.culled != null ? o.culled : culled
		});
}
