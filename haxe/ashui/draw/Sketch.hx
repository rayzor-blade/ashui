package ashui.draw;

import ashui.draw.SketchInput;

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

	/** What the user did since the previous frame, in order: every transition, even those that began and ended between frames. **/
	public final events:Array<SketchEvent>;

	/** The pointer, buttons, keys and touches as they are now. **/
	public final input:SketchInput;

	public function new(width:Float, height:Float, frame:Int, ?input:SketchInput) {
		super(width, height);
		this.frame = frame;
		this.input = input == null ? new SketchInput() : input;
		events = this.input.take();
	}

	/** Whether `draw` kept the last frame's picture. **/
	public var kept(default, null) = false;

	/** Whether `draw` asked to rest. **/
	public var resting(default, null) = false;

	/** Nothing changed this frame: the canvas keeps what it last drew, and asks the window for no frame. The next frame still runs. **/
	public function unchanged():Void
		kept = true;

	/**
		Nothing changed, and nothing will until the user does something, the canvas
		resizes, or the program calls the canvas's `wake()`: the sketch is not run
		again until then, and an idle window is left to sleep.
	**/
	public function rest():Void {
		kept = true;
		resting = true;
	}

	/** The pointer's place in the sketch. **/
	public var mouseX(get, never):Float;

	public var mouseY(get, never):Float;

	public var mouseIsPressed(get, never):Bool;

	inline function get_mouseX():Float
		return input.mouseX;

	inline function get_mouseY():Float
		return input.mouseY;

	inline function get_mouseIsPressed():Bool
		return input.mouseIsPressed;

	/** Whether the key at this physical position is held. **/
	public function keyIsDown(key:window.PhysicalKey):Bool
		return input.keyIsDown(key);

	/** A painter over this frame, its fill black and no stroke. **/
	public function painter():Painter
		return new Painter(this);
}
