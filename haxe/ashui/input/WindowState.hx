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
}
