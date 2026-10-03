package ashui.input;

import ashui.reactive.Signal;

/**
	Whether the window is the one the user is working in, and whether any of
	it can be seen, as signals. A window's loop sets them from the system;
	offscreen they stay true. A text field hides its caret and stops blinking
	while the window is inactive or hidden, as macOS does.
**/
class WindowState {
	/** The window has keyboard focus: it is the frontmost, active one. **/
	public static final active:Signal<Bool> = Signal.make(true);

	/** Some of the window can be seen: it is not minimized, hidden or wholly covered. **/
	public static final visible:Signal<Bool> = Signal.make(true);

	/**
		Where the focused text's caret is, in the window's layout units, while
		text has focus; null otherwise. The window turns its input method on
		while it is set and shows the method's candidates beside it.
	**/
	public static final textCaret:Signal<Null<CaretArea>> = Signal.make((null : Null<CaretArea>));
}

/** A caret's rect in the window, in layout units. **/
typedef CaretArea = {x:Float, y:Float, width:Float, height:Float};
