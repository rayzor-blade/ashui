package ashui.draw;

import ashui.input.Events.CompositionEvent;
import ashui.input.Events.FocusEvent;
import ashui.input.Events.KeyEvent;
import ashui.input.Events.PointerEvent;
import ashui.input.Events.TextInputEvent;
import ashui.input.Events.TouchEvent;
import window.Key;
import window.Modifiers;
import window.MouseButton;
import window.PhysicalKey;

/** One thing the user did while a sketch ran, in the sketch's own coordinates. **/
enum SketchEvent {
	PointerDown(x:Float, y:Float, button:MouseButton, modifiers:Modifiers);
	PointerUp(x:Float, y:Float, button:MouseButton, modifiers:Modifiers);
	PointerMove(x:Float, y:Float, modifiers:Modifiers);
	Wheel(x:Float, y:Float, dx:Float, dy:Float, modifiers:Modifiers);
	KeyDown(key:Key, physicalKey:PhysicalKey, repeat:Bool, modifiers:Modifiers);
	KeyUp(key:Key, physicalKey:PhysicalKey, modifiers:Modifiers);
	/** Text typed, or committed by an input method. **/
	Text(text:String);
	/** Text an input method is composing, empty when it stops; `cursor` is -1 for none. **/
	Composition(text:String, cursor:Int);
	Focus;
	Blur;
	Resize(width:Float, height:Float);
	TouchStart(id:Int, x:Float, y:Float);
	TouchMove(id:Int, x:Float, y:Float);
	TouchEnd(id:Int, x:Float, y:Float);
	TouchCancel(id:Int, x:Float, y:Float);
}

/**
	What a canvas's sketch has been told since its last frame, and where the
	pointer and keys are now. `events` keeps every transition in the order it
	came, so a click that began and ended between two frames reaches `draw` as
	both; the polled fields are for sketches that only need the latest state.
	A canvas with a sketch takes the pointer while a button is down, so a drag
	that leaves it goes on.
**/
class SketchInput {
	/** What happened since the last frame, in order; the frame that reads it is given a copy. **/
	var pending:Array<SketchEvent> = [];

	/** The pointer's place in the sketch, and whether it was last seen over it. **/
	public var mouseX(default, null) = 0.0;

	public var mouseY(default, null) = 0.0;

	/** Buttons now held. **/
	public var buttons(default, null):Array<MouseButton> = [];

	/** Whether any button is held. **/
	public var mouseIsPressed(get, never):Bool;

	/** Whether the canvas has focus, and so gets the keys. **/
	public var focused(default, null) = false;

	final keys:Array<PhysicalKey> = [];
	final touches = new Map<Int, {x:Float, y:Float}>();

	/** Called when an event arrives, for a sketch that rested to start again. **/
	public var onActivity:Null<Void->Void> = null;

	public function new() {}

	function note(e:SketchEvent):Void {
		pending.push(e);
		if (onActivity != null)
			onActivity();
	}

	inline function get_mouseIsPressed():Bool
		return buttons.length > 0;

	/** Whether the key with this physical position is held. **/
	public function keyIsDown(key:PhysicalKey):Bool {
		for (k in keys)
			if (Type.enumEq(k, key))
				return true;
		return false;
	}

	/** The places of the touches now down, by touch. **/
	public function touchesDown():Map<Int, {x:Float, y:Float}>
		return touches.copy();

	/** Whether anything happened since the last frame took the events. **/
	public function hasEvents():Bool
		return pending.length > 0;

	/** The events since the last call, which they leave empty. **/
	public function take():Array<SketchEvent> {
		var out = pending;
		pending = [];
		return out;
	}

	function holds(button:MouseButton):Int {
		for (i in 0...buttons.length)
			if (Type.enumEq(buttons[i], button))
				return i;
		return -1;
	}

	public function pointerDown(e:PointerEvent):Void {
		e.capturePointer();
		mouseX = e.localX;
		mouseY = e.localY;
		var b = e.button == null ? MouseButton.Left : e.button;
		if (holds(b) < 0)
			buttons.push(b);
		note(PointerDown(mouseX, mouseY, b, e.modifiers));
	}

	public function pointerUp(e:PointerEvent):Void {
		mouseX = e.localX;
		mouseY = e.localY;
		var b = e.button == null ? MouseButton.Left : e.button;
		var at = holds(b);
		if (at >= 0)
			buttons.splice(at, 1);
		note(PointerUp(mouseX, mouseY, b, e.modifiers));
	}

	public function pointerMove(e:PointerEvent):Void {
		mouseX = e.localX;
		mouseY = e.localY;
		note(PointerMove(mouseX, mouseY, e.modifiers));
	}

	public function wheel(e:PointerEvent):Void {
		note(Wheel(e.localX, e.localY, e.deltaX, e.deltaY, e.modifiers));
		e.stopPropagation();
	}

	public function keyDown(e:KeyEvent):Void {
		if (!keyIsDown(e.physicalKey))
			keys.push(e.physicalKey);
		note(KeyDown(e.key, e.physicalKey, e.repeat, e.modifiers));
	}

	public function keyUp(e:KeyEvent):Void {
		var i = keys.length;
		while (i-- > 0)
			if (Type.enumEq(keys[i], e.physicalKey))
				keys.splice(i, 1);
		note(KeyUp(e.key, e.physicalKey, e.modifiers));
	}

	public function text(e:TextInputEvent):Void
		note(Text(e.text));

	public function composition(e:CompositionEvent):Void
		note(Composition(e.text, e.cursor));

	public function focus(_:FocusEvent):Void {
		focused = true;
		note(Focus);
	}

	public function blur(_:FocusEvent):Void {
		focused = false;
		// Keys held when focus left would never be seen to go up.
		keys.resize(0);
		note(Blur);
	}

	public function resized(width:Float, height:Float):Void
		note(Resize(width, height));

	public function touch(e:TouchEvent, kind:Int):Void {
		touches.set(e.id, {x: e.localX, y: e.localY});
		note(switch kind {
			case 0: TouchStart(e.id, e.localX, e.localY);
			case 1: TouchMove(e.id, e.localX, e.localY);
			case 2: TouchEnd(e.id, e.localX, e.localY);
			default: TouchCancel(e.id, e.localX, e.localY);
		});
		if (kind >= 2)
			touches.remove(e.id);
	}
}
