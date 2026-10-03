package ashui.input;

/**
	Plain text to copy and paste. In a windowed build it is the system's
	clipboard, through hlwindow; elsewhere, such as offscreen or in tests,
	it is held in the process.
**/
class Clipboard {
	static var held = "";

	/** The clipboard's text; empty when it holds none. **/
	public static function text():String {
		#if (hlwindow || ashui_window)
		return switch window.Window.clipboardText() {
			case Some(t): t;
			case None: "";
		}
		#else
		return held;
		#end
	}

	public static function setText(text:String):Void {
		#if (hlwindow || ashui_window)
		window.Window.setClipboardText(text);
		#else
		held = text;
		#end
	}
}
