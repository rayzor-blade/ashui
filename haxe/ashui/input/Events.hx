package ashui.input;

import ashui.layout.Node;
import window.Key;
import window.KeyLocation;
import window.Modifiers;
import window.ModifiersKeyState;
import window.MouseButton;
import window.PhysicalKey;

/**
	What an input event is going through. An event starts at its `target` and
	bubbles: it is handed to the target's handlers, then to each ancestor's,
	`currentTarget` naming the one whose handler runs, until a handler calls
	`stopPropagation`. Keys, buttons and modifiers are hlwindow's own types.
**/
class InputEvent {
	/** No modifier key held. **/
	public static final NO_MODIFIERS:Modifiers = State(false, false, false, false, Unknown, Unknown, Unknown, Unknown, Unknown, Unknown, Unknown,
		Unknown);

	/** Where the event started: the topmost node under the pointer, or the focused one. **/
	public var target(default, null):Node;

	/** The node whose handler is running. **/
	public var currentTarget(default, null):Node;

	/** The modifier keys held; `shift`, `control`, `alt` and `superKey` read it. **/
	public final modifiers:Modifiers;

	/** Whether a handler called `stopPropagation`. **/
	public var propagationStopped(default, null) = false;

	function new(target:Node, modifiers:Modifiers) {
		this.target = target;
		this.currentTarget = target;
		this.modifiers = modifiers;
	}

	/** Hands the event to no further ancestor. **/
	public function stopPropagation():Void {
		propagationStopped = true;
	}

	public var shift(get, never):Bool;

	public var control(get, never):Bool;

	public var alt(get, never):Bool;

	/** Command on macOS, the Windows key elsewhere. **/
	public var superKey(get, never):Bool;

	function get_shift()
		return switch modifiers {
			case State(v, _, _, _, _, _, _, _, _, _, _, _): v;
		}

	function get_control()
		return switch modifiers {
			case State(_, v, _, _, _, _, _, _, _, _, _, _): v;
		}

	function get_alt()
		return switch modifiers {
			case State(_, _, v, _, _, _, _, _, _, _, _, _): v;
		}

	function get_superKey()
		return switch modifiers {
			case State(_, _, _, v, _, _, _, _, _, _, _, _): v;
		}

	@:allow(ashui.input)
	function at(node:Node):Void {
		currentTarget = node;
	}
}

/** A pointer moved, pressed, released, clicked, entered, left or scrolled. **/
class PointerEvent extends InputEvent {
	/** Where the pointer is in the window, in layout units. **/
	public final x:Float;

	public final y:Float;

	/** Where it is in `currentTarget`'s own coordinates, from its top-left, after its transforms. **/
	public var localX(default, null):Float;

	public var localY(default, null):Float;

	/** The button pressed or released; null for movement, enter, leave and wheel. **/
	public final button:Null<MouseButton>;

	/** Presses in quick succession at about the same place, counting this one: 2 for a double-click. **/
	public var clickCount(default, null) = 1;

	/** How far a wheel or trackpad scrolled, in layout units; 0 for other events. **/
	public final deltaX:Float;

	public final deltaY:Float;

	@:allow(ashui.input)
	function new(target:Node, x:Float, y:Float, button:Null<MouseButton>, modifiers:Modifiers, deltaX = 0.0, deltaY = 0.0) {
		super(target, modifiers);
		this.x = x;
		this.y = y;
		this.localX = x;
		this.localY = y;
		this.button = button;
		this.deltaX = deltaX;
		this.deltaY = deltaY;
	}

	@:allow(ashui.input)
	function local(x:Float, y:Float):Void {
		localX = x;
		localY = y;
	}

	@:allow(ashui.input)
	function count(n:Int):Void {
		clickCount = n;
	}
}

/** A key went down or up while a node had focus. **/
class KeyEvent extends InputEvent {
	/** What the key means under the current layout. **/
	public final key:Key;

	/** Which key it is on the keyboard, whatever the layout. **/
	public final physicalKey:PhysicalKey;

	/** Where the key is: left or right, as of the two Shifts, on the keypad, or neither. **/
	public final location:KeyLocation;

	/** True for the repeats a held key sends after its first press. **/
	public final repeat:Bool;

	/** Whether a handler called `preventDefault`. **/
	public var defaultPrevented(default, null) = false;

	@:allow(ashui.input)
	function new(target:Node, key:Key, physicalKey:PhysicalKey, location:KeyLocation, repeat:Bool, modifiers:Modifiers) {
		super(target, modifiers);
		this.key = key;
		this.physicalKey = physicalKey;
		this.location = location;
		this.repeat = repeat;
	}

	/** Stops what ashui does with the key afterwards: Tab moving focus, Enter or Space clicking. **/
	public function preventDefault():Void {
		defaultPrevented = true;
	}
}

/** Text was typed, or committed by an input method, while a node had focus. **/
class TextInputEvent extends InputEvent {
	/** The text to insert. **/
	public final text:String;

	@:allow(ashui.input)
	function new(target:Node, text:String, modifiers:Modifiers) {
		super(target, modifiers);
		this.text = text;
	}
}

/** A node gained or lost focus. These do not bubble. **/
class FocusEvent extends InputEvent {
	/** True when the keyboard moved focus, the case `focus-visible:` styles. **/
	public final visible:Bool;

	@:allow(ashui.input)
	function new(target:Node, visible:Bool) {
		super(target, InputEvent.NO_MODIFIERS);
		this.visible = visible;
	}
}

/**
	An input method's text being composed, not yet typed: the marked text a
	Japanese, Chinese or Korean input method shows while a word is chosen,
	or an accent waiting for its letter. Empty when composing ends. `cursor`
	is where the input method's own caret is in `text`, or -1 for none.
**/
class CompositionEvent extends InputEvent {
	public final text:String;
	public final cursor:Int;

	@:allow(ashui.input)
	function new(target:Node, text:String, cursor:Int) {
		super(target, InputEvent.NO_MODIFIERS);
		this.text = text;
		this.cursor = cursor;
	}
}
