package ashui.components.code;

typedef CodeSelection = {final caret:Int; final anchor:Int;}
/** A replacement of the text from `from` to `to`, offsets as `CodeEditor.select` takes them. **/
typedef CodeEdit = {final from:Int; final to:Int; final text:String;}
/** A stretch of the text, where it was before the edit, replaced by another. **/
typedef CodePatch = {final from:Int; final removed:String; final inserted:String;}
private typedef Edit = {parts:Array<CodePatch>, before:CodeSelection, after:CodeSelection, bytes:Int};

/**
	Bounded replacement patches; history never retains a full document per keystroke (e53597f). An edit is one
	patch for typing, and several when code replaces stretches far apart as one step (a rename), so what lies
	between them is not kept.
**/
class CodeHistory {
	final undoStack:Array<Edit> = [];
	final redoStack:Array<Edit> = [];
	var bytes = 0;
	public final limit:Int;
	public function new(limit = 1024 * 1024) this.limit = limit;
	public function clear():Void { undoStack.resize(0); redoStack.resize(0); bytes = 0; }

	/** Records the change from `before` to `after` as one patch. **/
	public function record(before:String, after:String, selection:CodeSelection, next:CodeSelection):Void {
		if (before == after) return;
		var from = 0, suffix = 0;
		while (from < before.length && from < after.length && before.charCodeAt(from) == after.charCodeAt(from)) from++;
		while (suffix < before.length - from && suffix < after.length - from
			&& before.charCodeAt(before.length - suffix - 1) == after.charCodeAt(after.length - suffix - 1)) suffix++;
		push([{from: from, removed: before.substring(from, before.length - suffix), inserted: after.substring(from, after.length - suffix)}], selection, next);
	}

	/** Records `parts`, in order and not overlapping, positions in the text before them, as one step. **/
	public function recordParts(parts:Array<CodePatch>, selection:CodeSelection, next:CodeSelection):Void {
		if (parts.length > 0) push(parts, selection, next);
	}

	function push(parts:Array<CodePatch>, selection:CodeSelection, next:CodeSelection):Void {
		var size = 64;
		for (part in parts) size += (part.removed.length + part.inserted.length) * 2 + 16;
		for (edit in redoStack) bytes -= edit.bytes;
		redoStack.resize(0);
		if (size > limit) { clear(); return; }
		undoStack.push({parts: parts, before: selection, after: next, bytes: size});
		bytes += size;
		while (bytes > limit || undoStack.length > 100) bytes -= undoStack.shift().bytes;
	}

	public function apply(value:String, redo:Bool):Null<{text:String, selection:CodeSelection}> {
		var source = redo ? redoStack : undoStack, target = redo ? undoStack : redoStack;
		if (source.length == 0) return null;
		var edit = source.pop();
		// Each part's place in the text it is applied to: after the parts before it have changed its length, when undoing.
		var text = value, shift = 0, places = [];
		for (part in edit.parts) {
			var remove = redo ? part.removed : part.inserted;
			places.push(part.from + (redo ? 0 : shift));
			shift += part.inserted.length - part.removed.length;
			if (text.substr(places[places.length - 1], remove.length) != remove) { clear(); return null; }
		}
		// From the last, so the places of those before it hold.
		var i = edit.parts.length;
		while (i-- > 0) {
			var part = edit.parts[i], remove = redo ? part.removed : part.inserted, insert = redo ? part.inserted : part.removed;
			text = text.substr(0, places[i]) + insert + text.substr(places[i] + remove.length);
		}
		target.push(edit);
		return {text: text, selection: redo ? edit.after : edit.before};
	}
}
