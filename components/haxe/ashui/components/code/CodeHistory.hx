package ashui.components.code;

typedef CodeSelection = {final caret:Int; final anchor:Int;}
private typedef Edit = {from:Int, removed:String, inserted:String, before:CodeSelection, after:CodeSelection, bytes:Int};

/** Bounded replacement patches; history never retains a full document per keystroke (e53597f). **/
class CodeHistory {
	final undoStack:Array<Edit> = [];
	final redoStack:Array<Edit> = [];
	var bytes = 0;
	public final limit:Int;
	public function new(limit = 1024 * 1024) this.limit = limit;
	public function clear():Void { undoStack.resize(0); redoStack.resize(0); bytes = 0; }
	public function record(before:String, after:String, selection:CodeSelection, next:CodeSelection):Void {
		if (before == after) return;
		var from = 0, suffix = 0;
		while (from < before.length && from < after.length && before.charCodeAt(from) == after.charCodeAt(from)) from++;
		while (suffix < before.length - from && suffix < after.length - from
			&& before.charCodeAt(before.length - suffix - 1) == after.charCodeAt(after.length - suffix - 1)) suffix++;
		var removed = before.substring(from, before.length - suffix), inserted = after.substring(from, after.length - suffix);
		var size = (removed.length + inserted.length) * 2 + 64;
		for (edit in redoStack) bytes -= edit.bytes;
		redoStack.resize(0);
		if (size > limit) { clear(); return; }
		undoStack.push({from: from, removed: removed, inserted: inserted, before: selection, after: next, bytes: size});
		bytes += size;
		while (bytes > limit || undoStack.length > 100) bytes -= undoStack.shift().bytes;
	}
	public function apply(value:String, redo:Bool):Null<{text:String, selection:CodeSelection}> {
		var source = redo ? redoStack : undoStack, target = redo ? undoStack : redoStack;
		if (source.length == 0) return null;
		var edit = source.pop();
		var remove = redo ? edit.removed : edit.inserted, insert = redo ? edit.inserted : edit.removed;
		if (value.substr(edit.from, remove.length) != remove) { clear(); return null; }
		target.push(edit);
		return {text: value.substr(0, edit.from) + insert + value.substr(edit.from + remove.length), selection: redo ? edit.after : edit.before};
	}
}
