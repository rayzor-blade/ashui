package ashui.input;

import haxe.io.Bytes;

/** One representation of what is on the clipboard: its MIME type and its bytes. **/
typedef ClipboardEntry = {
	final type:String;
	final data:Bytes;
}

/**
	What is copied and pasted, as text or as data of any MIME type: HTML, an
	image as `image/png`, files as `text/uri-list` (`file://` URIs, one a
	line). A copy can hold several representations of one thing, so a paste
	takes the best one it understands. In a windowed build it is the
	system's clipboard, through hlwindow; elsewhere, such as offscreen or in
	tests, it is held in the process.

	`text/plain` is UTF-8 text, and `text` and `setText` read and write it.
	On Wayland a write is taken only after the window has had input.
**/
class Clipboard {
	public static inline var TEXT = "text/plain";

	static var held:Array<ClipboardEntry> = [];

	/** The clipboard's text; empty when it holds none. **/
	public static function text():String {
		#if (hlwindow || ashui_window)
		return switch window.Window.clipboardText() {
			case Some(t): t;
			case None: "";
		}
		#else
		var d = data(TEXT);
		return d == null ? "" : d.toString();
		#end
	}

	/** Puts `text` on the clipboard, in place of everything there. **/
	public static function setText(text:String):Void {
		#if (hlwindow || ashui_window)
		window.Window.setClipboardText(text);
		#else
		held = [{type: TEXT, data: Bytes.ofString(text)}];
		#end
	}

	/** The MIME types on the clipboard, the best first. **/
	public static function types():Array<String> {
		#if (hlwindow || ashui_window)
		return [for (i in 0...window.Window.clipboardTypeCount()) window.Window.clipboardType(i)];
		#else
		return [for (e in held) e.type];
		#end
	}

	/** The clipboard's data as `mimeType`, or null when it has none of that type. **/
	public static function data(mimeType:String):Null<Bytes> {
		#if (hlwindow || ashui_window)
		return switch window.Window.clipboardData(mimeType) {
			case Some(b): b;
			case None: null;
		}
		#else
		for (e in held)
			if (e.type == mimeType)
				return e.data;
		return null;
		#end
	}

	/**
		Puts `entries` on the clipboard together, in place of everything
		there, the best first: one copied thing in each form it can take,
		such as `text/html` with a `text/plain` fallback. False when the
		system did not take it.
	**/
	public static function write(entries:Array<ClipboardEntry>):Bool {
		#if (hlwindow || ashui_window)
		var items = window.ClipboardItems.create();
		for (e in entries)
			items.add(e.type, e.data);
		return items.write();
		#else
		held = entries.copy();
		return true;
		#end
	}
}
