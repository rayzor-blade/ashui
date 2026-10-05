package ashui.draw3d;

/**
	Where a material's textures sit on its surface, as glTF's
	`KHR_texture_transform` places them: each texture coordinate scaled by
	`scaleX` and `scaleY`, turned `rotation` radians counter-clockwise
	about the origin, then moved by `offsetX` and `offsetY`. A scale of 3
	repeats a texture three times across where it was once.

	```haxe
	new Material({baseColorTexture: rock, textureTransform: new TextureTransform(4, 4)});
	```
**/
class TextureTransform {
	public static final IDENTITY = new TextureTransform();

	public final scaleX:Float;
	public final scaleY:Float;
	public final rotation:Float;
	public final offsetX:Float;
	public final offsetY:Float;

	public function new(scaleX = 1.0, scaleY = 1.0, rotation = 0.0, offsetX = 0.0, offsetY = 0.0) {
		this.scaleX = scaleX;
		this.scaleY = scaleY;
		this.rotation = rotation;
		this.offsetX = offsetX;
		this.offsetY = offsetY;
	}

	/** Its rotation and scale as a 2×2 matrix, by rows: `u' = a u + b v + offsetX`, `v' = c u + d v + offsetY`. **/
	public function matrix():{a:Float, b:Float, c:Float, d:Float} {
		var c = Math.cos(rotation), s = Math.sin(rotation);
		return {a: c * scaleX, b: -s * scaleY, c: s * scaleX, d: c * scaleY};
	}
}
