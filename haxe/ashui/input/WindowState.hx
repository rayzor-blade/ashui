package ashui.input;

import ashui.reactive.Signal;

/**
	Whether the window is the one the user is working in, and whether any of
	it can be seen, as signals. A window's loop sets them from the system;
	offscreen they stay true. A text field hides its caret and stops blinking
	while the window is inactive or hidden, as macOS does.
**/
class WindowState {
	static final local = new ashui.core.UiContext.Local(() -> new WindowSignals());
	/** The window has keyboard focus: it is the frontmost, active one. **/
	public static var active(get, never):Signal<Bool>;
	static function get_active() return local.value.active;

	/** Some of the window can be seen: it is not minimized, hidden or wholly covered. **/
	public static var visible(get, never):Signal<Bool>;
	static function get_visible() return local.value.visible;

	/**
		Where the focused text's caret is, in the window's layout units, while
		text has focus; null otherwise. The window turns its input method on
		while it is set and shows the method's candidates beside it.
	**/
	public static var textCaret(get, never):Signal<Null<CaretArea>>;
	static function get_textCaret() return local.value.textCaret;
}

/** A caret's rect in the window, in layout units. **/
typedef CaretArea = {x:Float, y:Float, width:Float, height:Float};

private class WindowSignals {
	public final active = Signal.make(true);
	public final visible = Signal.make(true);
	public final textCaret = Signal.make((null:Null<CaretArea>));
	public function new() {}
}
