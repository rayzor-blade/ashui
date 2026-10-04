package ashui.draw;

/**
	A drawing that runs, frame after frame: `setup` once, before the first
	`draw`; then `draw` every frame, given the seconds since it started,
	`t`, and since the last frame, `dt`, on the animation scheduler's
	clock, so a recording or a test steps it as it steps animations. What
	it keeps from frame to frame, positions and velocities, it keeps in
	its own fields. A canvas runs one with its `sketch`.
**/
interface Sketch {
	function setup(ctx:SketchContext):Void;
	function draw(ctx:SketchContext, t:Float, dt:Float):Void;
}

/** A sketch's frame: a `DrawContext` of the canvas's size, which frame it is, and a `Painter` over it. **/
class SketchContext extends DrawContext {
	/** Frames drawn before this one: 0 in `setup` and the first `draw`. **/
	public final frame:Int;

	public function new(width:Float, height:Float, frame:Int) {
		super(width, height);
		this.frame = frame;
	}

	/** A painter over this frame, its fill black and no stroke. **/
	public function painter():Painter
		return new Painter(this);
}
