package ashui.components.code;

import ashui.reactive.Signal;

/**
 * A document's data, independent of its mounted editor. Keep this when replacing
 * a view: text, bounded undo patches, syntax/fold caches and navigation survive.
 * Row pools, measured text, input handlers and minimap resources belong to the view.
 * One state serves one editor at a time; a replacement may mount before its old
 * view is disposed. Disposing the current view removes its capture hook.
 */
@:allow(ashui.components.CodeEditor)
class CodeEditorState {
	public final value:Signal<String>;
	public final history = new CodeHistory();
	public var document(default, null):Null<CodeDocument>;
	public var annotations(default, null):Null<CodeAnnotations>;
	public var caret(default, null) = 0;
	public var anchor(default, null) = 0;
	public var scrollX(default, null) = 0.;
	public var scrollY(default, null) = 0.;
	var knownValue:String;
	var annotatedText:String;
	var generation = 0;
	var capture:Null<Void->Void>;

	public function new(?value:Signal<String>) {
		this.value = value == null ? Signal.make("") : value;
		knownValue = annotatedText = this.value.get();
	}

	/** Whether a view currently owns this state. No view closure is kept when false. */
	public var mounted(get, never):Bool;
	function get_mounted():Bool return capture != null;

	function resume():Int {
		if (capture != null) capture();
		capture = null;
		return ++generation;
	}

	function attach(token:Int, snapshot:Void->Void):Void {
		if (token == generation) capture = snapshot;
	}

	function detach(token:Int):Void {
		if (token != generation) return;
		if (capture != null) capture();
		capture = null;
	}
}
