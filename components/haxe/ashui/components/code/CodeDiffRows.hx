package ashui.components.code;

import ashui.components.code.CodeDiffer.CodeChange;
import ashui.components.code.CodeDiffer.CodeWordChange;

/** Content type of a diff row. **/
enum abstract CodeDiffRowKind(Int) {
	/** An unchanged line present in both texts. **/
	var Context = 0;

	/** An original-only line. Split layout adds a filler on the modified side. **/
	var Removed = 1;

	/** A modified-only line. Split layout adds a filler on the original side. **/
	var Added = 2;

	/** A paired removed and added line in split layout. **/
	var Edited = 3;

	/** Collapsed unchanged lines, counted by `hidden`. **/
	var Placeholder = 4;
}

/**
	Compact row mapping for inline and split diffs.

	Rows include context, changes, and placeholders for long unchanged runs.
	Inline layout lists removals before additions. Split layout pairs edited
	lines and inserts fillers when one side has no match. Five integers per
	row avoid allocating a row object for every source line.
**/
class CodeDiffRows {
	static inline var STRIDE = 5;

	/** Minimum unchanged run worth collapsing after accounting for the placeholder row. **/
	static inline var HIDE = 3;

	final data:Array<Int>;
	final firstRows:Array<Int>;
	final partnerOf:Map<Int, Int>;
	final marks = new Map<Int, Null<Array<CodeWordChange>>>();
	final widest = [-1, -1];
	final original:Array<String>;
	final modified:Array<String>;

	/** Total row count. **/
	public final count:Int;

	/** Changes used to build the row mapping. **/
	public final changes:Array<CodeChange>;

	/** Whether the mapping uses split layout. **/
	public final split:Bool;

	function new(data:Array<Int>, firstRows:Array<Int>, partnerOf:Map<Int, Int>, original:Array<String>, modified:Array<String>, changes:Array<CodeChange>,
			split:Bool) {
		this.data = data;
		this.count = Std.int(data.length / STRIDE);
		this.firstRows = firstRows;
		this.partnerOf = partnerOf;
		this.original = original;
		this.modified = modified;
		this.changes = changes;
		this.split = split;
	}

	/** Returns the zero-based original line, or -1 for a filler or an added-only row. **/
	public inline function originalAt(row:Int):Int
		return data[row * STRIDE];

	/** Returns the zero-based modified line, or -1 when this row has none. **/
	public inline function modifiedAt(row:Int):Int
		return data[row * STRIDE + 1];

	/** Returns the change index for a row, or -1 for context outside changes. **/
	public inline function changeAt(row:Int):Int
		return data[row * STRIDE + 2];

	/** Returns the collapsed line count for a placeholder, or zero for other rows. **/
	public inline function hiddenAt(row:Int):Int
		return data[row * STRIDE + 3];

	/** Returns the modified-line position corresponding to a row, including removal positions. **/
	inline function anchorAt(row:Int):Int
		return data[row * STRIDE + 4];

	public function kindAt(row:Int):CodeDiffRowKind {
		if (hiddenAt(row) > 0)
			return Placeholder;
		var o = originalAt(row), m = modifiedAt(row);
		return o >= 0 && m >= 0 ? (changeAt(row) >= 0 ? Edited : Context) : o >= 0 ? Removed : Added;
	}

	/** Returns whether a row begins a change. **/
	public inline function firstOfChange(row:Int):Bool {
		var c = changeAt(row);
		return c >= 0 && firstRows[c] == row;
	}

	/** Returns the first row of a change. **/
	public inline function rowOfChange(change:Int):Int
		return firstRows[change];

	/** Returns source text on the requested side, or null for fillers and placeholders. **/
	public function textAt(row:Int, originalSide:Bool):Null<String> {
		if (hiddenAt(row) > 0)
			return null;
		var line = originalSide ? originalAt(row) : modifiedAt(row);
		return line < 0 ? null : originalSide ? original[line] : modified[line];
	}

	/**
		Finds the row displaying or hiding a modified source line. Missing lines
		map to their insertion position; positions after the final line return
		the total row count.
	**/
	public function rowOfModified(line:Int):Int {
		var low = 0, high = count;
		while (low < high) {
			var middle = (low + high) >> 1;
			if (anchorAt(middle) < line)
				low = middle + 1;
			else
				high = middle;
		}
		if (low > 0 && hiddenAt(low - 1) > 0 && modifiedAt(low - 1) + hiddenAt(low - 1) > line)
			return low - 1;
		// Removed rows at the same place come before the line's own row.
		var row = low;
		while (row < count && anchorAt(row) == line && modifiedAt(row) < 0 && hiddenAt(row) == 0)
			row++;
		return row < count && modifiedAt(row) == line ? row : low;
	}

	/** Finds the first row at or after an original source line. Scans the row mapping and is slower than `rowOfModified`. **/
	public function rowOfOriginal(line:Int):Int {
		for (row in 0...count) {
			var o = originalAt(row);
			if (o >= line || (hiddenAt(row) > 0 && o + hiddenAt(row) > line))
				return row;
		}
		return count;
	}

	/**
		Returns cached word-change ranges for one side of an edited row.
		Returns null for unpaired lines, dissimilar lines, or rows without edits.
	**/
	public function wordsAt(row:Int, originalSide:Bool):Null<Array<{from:Int, to:Int}>> {
		var o = originalAt(row), m = modifiedAt(row);
		if (hiddenAt(row) > 0 || changeAt(row) < 0)
			return null;
		// A line is another's partner when the pairing says so, in whichever row each of the two is. A change with as many
		// lines on each side pairs them by position, which is worked out; the pairs of any other are in `partnerOf`.
		var change = changes[changeAt(row)], even = change.originalLines == change.modifiedLines;
		if (o < 0 && m >= 0) {
			var p = even ? change.originalStart + m - change.modifiedStart : partnerOf.get(-m - 1);
			if (p == null)
				return null;
			o = p;
		} else if (m < 0 && o >= 0) {
			var p = even ? change.modifiedStart + o - change.originalStart : partnerOf.get(o);
			if (p == null)
				return null;
			m = p;
		}
		if (o < 0 || m < 0)
			return null;
		var found:Null<Array<CodeWordChange>>;
		if (marks.exists(o))
			found = marks.get(o);
		else {
			found = CodeDiffer.words(original[o], modified[m]);
			marks.set(o, found);
		}
		if (found == null || found.length == 0)
			return null;
		return [for (w in found) originalSide ? {from: w.originalFrom, to: w.originalTo} : {from: w.modifiedFrom, to: w.modifiedTo}];
	}

	/**
		Returns the widest displayed line in columns, expanding tab stops and
		limiting long lines to `CodeDiffText.CLIP`. Computes once per side.
	**/
	public function widestColumn(originalSide:Bool, tabSize:Int):Int {
		var at = originalSide ? 0 : 1;
		if (widest[at] < 0) {
			var most = 0, lines = originalSide ? original : modified;
			for (r in 0...count) {
				var line = originalSide ? originalAt(r) : modifiedAt(r);
				if (line < 0 || hiddenAt(r) > 0)
					continue;
				var text = lines[line], column = 0, shown = text.length < CodeDiffText.CLIP ? text.length : CodeDiffText.CLIP;
				for (k in 0...shown)
					column += StringTools.fastCodeAt(text, k) == "\t".code ? tabSize - column % tabSize : 1;
				if (text.length > CodeDiffText.CLIP)
					column++;
				if (column > most)
					most = column;
			}
			widest[at] = most;
		}
		return widest[at];
	}

	/**
		Builds the row mapping. `context` keeps unchanged lines around each change;
		a negative value keeps all lines. Other long runs become placeholders
		unless `isOpen` marks their first hidden modified line as expanded.
		A comparison without changes keeps every line.
	**/
	public static function build(original:Array<String>, modified:Array<String>, changes:Array<CodeChange>, split:Bool, context:Int, ?isOpen:Int->Bool):CodeDiffRows {
		var data = new Array<Int>(), firstRows = new Array<Int>(), partnerOf = new Map<Int, Int>();
		var collapse = context >= 0 && changes.length > 0;
		inline function row(o:Int, m:Int, change:Int, hidden:Int, anchor:Int):Void {
			data.push(o);
			data.push(m);
			data.push(change);
			data.push(hidden);
			data.push(anchor);
		}
		function unchanged(o:Int, m:Int, length:Int, atStart:Bool, atEnd:Bool):Void {
			if (length <= 0)
				return;
			var lead = atStart ? 0 : context, trail = atEnd ? 0 : context, hidden = length - lead - trail;
			if (!collapse || hidden < HIDE || (isOpen != null && isOpen(m + lead))) {
				for (i in 0...length)
					row(o + i, m + i, -1, 0, m + i);
				return;
			}
			for (i in 0...lead)
				row(o + i, m + i, -1, 0, m + i);
			row(o + lead, m + lead, -1, hidden, m + lead);
			for (i in length - trail...length)
				row(o + i, m + i, -1, 0, m + i);
		}
		var o = 0, m = 0;
		for (ci in 0...changes.length) {
			var c = changes[ci];
			unchanged(o, m, c.originalStart - o, ci == 0 && o == 0, false);
			firstRows.push(Std.int(data.length / STRIDE));
			var pairs = CodeDiffer.pairs(original, modified, c);
			// A change with equal sides pairs by position, which `wordsAt` works out, so a file rewritten whole makes no table.
			if (c.originalLines != c.modifiedLines) {
				var i = 0;
				while (i < pairs.length) {
					partnerOf.set(pairs[i], pairs[i + 1]);
					partnerOf.set(-pairs[i + 1] - 1, pairs[i]);
					i += 2;
				}
			}
			var oEnd = c.originalStart + c.originalLines, mEnd = c.modifiedStart + c.modifiedLines;
			if (!split) {
				for (k in c.originalStart...oEnd)
					row(k, -1, ci, 0, c.modifiedStart);
				for (k in c.modifiedStart...mEnd)
					row(-1, k, ci, 0, k);
			} else {
				var oi = c.originalStart, mi = c.modifiedStart;
				// The lines before a pair, or after the last, are opposite each other by position, with fillers where one side runs out.
				function gap(oTo:Int, mTo:Int):Void {
					var a = oTo - oi, b = mTo - mi;
					for (k in 0...(a > b ? a : b))
						row(k < a ? oi + k : -1, k < b ? mi + k : -1, ci, 0, k < b ? mi + k : mi + b);
				}
				var j = 0;
				while (j < pairs.length) {
					gap(pairs[j], pairs[j + 1]);
					row(pairs[j], pairs[j + 1], ci, 0, pairs[j + 1]);
					oi = pairs[j] + 1;
					mi = pairs[j + 1] + 1;
					j += 2;
				}
				gap(oEnd, mEnd);
			}
			o = oEnd;
			m = mEnd;
		}
		unchanged(o, m, original.length - o, changes.length == 0, true);
		return new CodeDiffRows(data, firstRows, partnerOf, original, modified, changes, split);
	}
}
