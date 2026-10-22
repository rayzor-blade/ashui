package ashui.components.code;

import ashui.core.externs.TextNative;
import ashui.ui.Text;
import ashui.ui.TextEditing.CaretStop;
import ashui.components.code.CodeDocument.CodeLine;

typedef CodeLineMetrics = {final expanded:String; final columns:Array<Int>; final stops:Array<CaretStop>; final width:Float;}

/** Native grapheme positions measured lazily, with at most 96 shaped lines retained (e53597f). **/
class CodeMetrics implements ashui.ui.TextGeometry {
	public var lineHeight(default, null) = 22.0;
	public var lines(default, null) = 1;
	public var characterWidth(default, null) = 8.0;
	public final document:CodeDocument;
	public var text:Text;
	public var syntax:CodeHighlighter;
	public final tabSize:Int;
	final cache = new haxe.ds.ObjectMap<CodeLine, CodeLineMetrics>();
	final recent:Array<CodeLine> = [];
	var valid = false;
	var widthGeneration = -1;
	var columns = 0;
	var widthRows:Array<Int>;

	public function new(document:CodeDocument, syntax:CodeHighlighter, tabSize:Int) {
		this.document = document; this.syntax = syntax; this.tabSize = tabSize;
	}

	public function invalidate():Void {
		cache.clear(); recent.resize(0); valid = false;
	}
	public function prepare(value:String):Void {
		if (document.update(value, syntax)) {
			// Retain only live, unchanged lines; evicted document lines must be released.
			for (line in recent.copy()) if (line.generation != document.generation) { cache.remove(line); recent.remove(line); }
		}
		lines = document.visible.length;
		if (!valid && text != null) {
			var out = new hl.Bytes(36), info = new hl.Bytes(16);
			var n = TextNative.blinc_text_carets(text.tree.ptr, text.node.id, ashui.core.Utf8.encode("M"), 0, 0, out, 3, info);
			if (n > 1) { lineHeight = info.getF32(0); characterWidth = out.getF32((n - 1) * 12 + 4); valid = true; }
		}
	}

	/** Document width is independent of the viewport; resizing reuses the column count. **/
	public function widestColumn():Int {
		if (widthGeneration == document.generation && widthRows == document.visible) return columns;
		columns = 0;
		for (source in document.visible) {
			var line = document.lines[source], column = 0;
			for (i in 0...line.text.length)
				column += StringTools.fastCodeAt(line.text, i) == "\t".code ? tabSize - column % tabSize : 1;
			if (column > columns) columns = column;
		}
		widthGeneration = document.generation;
		widthRows = document.visible;
		return columns;
	}

	public function measure(line:CodeLine):CodeLineMetrics {
		var found = cache.get(line);
		if (found != null) { recent.remove(line); recent.push(line); return found; }
		var columns:Array<Int> = [], column = 0, expanded = new StringBuf();
		for (i in 0...line.text.length) {
			columns.push(column);
			if (line.text.charAt(i) == "\t") {
				var count = tabSize - column % tabSize;
				for (_ in 0...count) expanded.add(" ");
				column += count;
			} else { expanded.add(line.text.charAt(i)); column++; }
		}
		columns.push(column);
		var shown = expanded.toString(), native:Array<CaretStop> = [];
		if (text != null) {
			var capacity = shown.length + 2, out = new hl.Bytes(capacity * 12), info = new hl.Bytes(16);
			var count = TextNative.blinc_text_carets(text.tree.ptr, text.node.id, ashui.core.Utf8.encode(shown), 0, 0, out, capacity, info);
			for (i in 0...count) native.push({index: Std.int(out.getF32(i * 12)), x: out.getF32(i * 12 + 4), line: 0});
		}
		if (native.length == 0) native.push({index: 0, x: 0, line: 0});
		var stops:Array<CaretStop> = [], at = 0;
		for (stop in native) {
			while (at < columns.length - 1 && columns[at] < stop.index) at++;
			if (columns[at] == stop.index) stops.push({index: at, x: stop.x, line: 0});
		}
		found = {expanded: shown, columns: columns, stops: stops, width: native[native.length - 1].x};
		cache.set(line, found); recent.push(line);
		if (recent.length > 96) cache.remove(recent.shift());
		return found;
	}

	public function sourceLine(row:Int):Int return document.visible[Std.int(Math.max(0, Math.min(document.visible.length - 1, row)))];
	public function xAt(line:CodeLine, column:Int):Float {
		var stops = measure(line).stops, low = 0, high = stops.length;
		while (low < high) {
			var middle = (low + high) >> 1;
			if (stops[middle].index <= column) low = middle + 1; else high = middle;
		}
		return low == 0 ? 0 : stops[low-1].x;
	}
	public function stopAt(index:Int):CaretStop {
		var source = document.lineAt(index), row = document.rows[source];
		var shown = sourceLine(row), line = document.lines[shown];
		return {index: index, line: row, x: xAt(line, shown == source ? index - line.start : line.text.length)};
	}
	public function indexAt(x:Float, row:Int):Int {
		var line = document.lines[sourceLine(row)], best = 0, distance = Math.POSITIVE_INFINITY;
		for (stop in measure(line).stops) if (Math.abs(stop.x - x) < distance) { best = stop.index; distance = Math.abs(stop.x - x); }
		return line.start + best;
	}
	public function lineWidth(row:Int):Float return measure(document.lines[sourceLine(row)]).width;
	public function lineEdge(index:Int, end:Bool):Int {
		var line = document.lines[sourceLine(document.rows[document.lineAt(index)])];
		return line.start + (end ? line.text.length : 0);
	}
	public function step(index:Int, forward:Bool):Int {
		var source = document.lineAt(index), row = document.rows[source], line = document.lines[source];
		var at = index - line.start, previous = 0;
		for (stop in measure(line).stops) {
			if (forward && stop.index > at) return line.start + stop.index;
			if (!forward && stop.index >= at) break;
			previous = stop.index;
		}
		if (forward) return row + 1 < document.visible.length ? document.lines[sourceLine(row + 1)].start : document.text.length;
		if (at > 0) return line.start + previous;
		return row > 0 ? lineEdge(document.lines[sourceLine(row - 1)].start, true) : 0;
	}
}
