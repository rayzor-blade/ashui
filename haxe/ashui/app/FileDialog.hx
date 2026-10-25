package ashui.app;

#if (hlwindow || ashui_window)
/** An asynchronous native file or folder selection attached to its requesting window. */
class FileDialog {
	static var next = 1;
	static final requests = new Map<Int, {context:ashui.core.UiContext, complete:Null<String>->Void}>();
	public static function available():Bool return Sys.systemName() == "Mac";

	/** Returns a cancellation function; completion receives null when cancelled. */
	public static function open(app:WindowedApp, options:{title:String, ?folder:Bool, ?directory:String, ?extensions:Array<String>}, complete:Null<String>->Void):Void->Void {
		if (!available() || app.disposed) throw "A native file dialog is unavailable for this window";
		var id = next++;
		var json = haxe.Json.stringify({id:id, view:haxe.Int64.toStr(app.window.raw(0)), title:options.title,
			folder:options.folder == true, directory:options.directory, extensions:options.extensions});
		requests.set(id, {context:app.context, complete:complete});
		if (!DialogNative.ui_dialog_open(@:privateAccess json.toUtf8())) { requests.remove(id); throw "The file browser could not be opened"; }
		var cancel = () -> { requests.remove(id); DialogNative.ui_dialog_cancel(id); };
		app.context.onCleanup(cancel);
		return cancel;
	}

	@:allow(ashui.app.WindowedApp)
	static function pump():Void {
		if (!available()) return;
		while (true) {
			var id = DialogNative.ui_dialog_poll();
			if (id == 0) return;
			var bytes = DialogNative.ui_dialog_take(id);
			var path = bytes == null ? null : @:privateAccess String.fromUTF8(bytes);
			var request = requests.get(id);
			requests.remove(id);
			if (request != null && !request.context.disposed) request.context.run(() -> request.complete(path == "" ? null : path));
		}
	}
}

#if ashui_caribou
/** The dialogs of the `ashui_desktop` Caribou plugin. **/
private class DialogNative {
	public static inline function ui_dialog_open(json:hl.Bytes):Bool
		return ashui_desktop.Desktop.dialog_open(@:privateAccess String.fromUTF8(json));

	public static inline function ui_dialog_poll():Int
		return ashui_desktop.Desktop.dialog_poll();

	public static function ui_dialog_take(id:Int):hl.Bytes {
		var path = ashui_desktop.Desktop.dialog_take(id);
		return path == "" ? null : @:privateAccess path.toUtf8();
	}

	public static inline function ui_dialog_cancel(id:Int):Void
		ashui_desktop.Desktop.dialog_cancel(id);
}
#else
@:hlNative("blinc_abi")
private extern class DialogNative {
	static function ui_dialog_open(json:hl.Bytes):Bool;
	static function ui_dialog_poll():Int;
	static function ui_dialog_take(id:Int):hl.Bytes;
	static function ui_dialog_cancel(id:Int):Void;
}
#end
#end
