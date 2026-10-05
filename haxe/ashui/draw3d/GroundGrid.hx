package ashui.draw3d;

/** A ground grid's settings, each optional; see `GroundGrid`. **/
typedef GroundGridOptions = {
	?size:Float,
	?subdivisions:Int,
	?minor:Int,
	?minorAlpha:Float,
	?major:Int,
	?majorAlpha:Float,
	?axes:Bool,
	?fadeNear:Float,
	?fadeFar:Float,
	?height:Float,
}

/**
	A ground grid under a 3D scene, as modelling tools draw one: a line each
	`size` units (major) and `subdivisions` between (minor), the X axis red
	and the Z axis blue where `axes` is set, fading out from `fadeNear` to
	`fadeFar` units from the camera. It lies flat at `height`, and meshes
	hide it where they are in front, so a model stands on it. Colours are
	`0xRRGGBB`, as `Brush` takes them. (Named apart from CSS's `display:
	grid`, `Display.Grid`, which a page usually has imported.)

	```haxe
	grid={GroundGrid.studio()}
	grid={new GroundGrid({size: 0.5, height: helmet.min.y})}
	```
**/
class GroundGrid {
	public final size:Float;
	public final subdivisions:Int;
	public final minor:Int;
	public final minorAlpha:Float;
	public final major:Int;
	public final majorAlpha:Float;
	public final axes:Bool;
	public final fadeNear:Float;
	public final fadeFar:Float;
	public final height:Float;

	public function new(?o:GroundGridOptions) {
		if (o == null)
			o = {};
		size = o.size != null ? o.size : 1;
		subdivisions = o.subdivisions != null ? o.subdivisions : 10;
		minor = o.minor != null ? o.minor : 0x808080;
		minorAlpha = o.minorAlpha != null ? o.minorAlpha : 0.25;
		major = o.major != null ? o.major : 0xa0a0a0;
		majorAlpha = o.majorAlpha != null ? o.majorAlpha : 0.55;
		axes = o.axes != false;
		fadeNear = o.fadeNear != null ? o.fadeNear : 4;
		fadeFar = o.fadeFar != null ? o.fadeFar : 20;
		height = o.height != null ? o.height : 0;
	}

	/** A studio floor: a line a unit, tenths between, axes coloured, fading out by twenty units; at `height`. **/
	public static function studio(height = 0.0):GroundGrid
		return new GroundGrid({height: height});
}
