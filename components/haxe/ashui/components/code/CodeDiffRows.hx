package ashui.components.code;

import ashui.components.code.CodeDiffer.CodeChange;
import ashui.components.code.CodeDiffer.CodeWordChange;

/** What a row of a diff shows. **/
enum abstract CodeDiffRowKind(Int) {
	/** A line both texts have, unchanged. **/
	var Context = 0;

	/** A line only the original has; in a side-by-side layout its modified side is a filler. **/
	var Removed = 1;

	/** A line only the modified text has; in a side-by-side layout its original side is a filler. **/
	var Added = 2;

	/** In a side-by-side layout, a removed line and an added line that are opposite each other. **/
	var Edited = 3;

	/** Unchanged lines left out, with the count in `hidden`. **/
	var Placeholder = 4;
}

/**
	The rows of a diff as a pane lists them, one height each: the unchanged lines around each change, the lines of the change,
	and a placeholder where a long run of unchanged lines is left out. Inline, the removed lines of a change come first and
	the added lines after; side by side, a removed and an added line share a row, with a filler opposite the one that has no
	partner. Rows are kept as integers, five to a row, so a file of tens of thousands of lines costs no object a row.
**/
class CodeDiffRows {
	static inline var STRIDE = 5;

	/** The fewest unchanged lines that are left out; fewer are shown, as a placeholder would take a row to save one. **/
	static inline var HIDE = 3;

	final data:Array<Int>;
	final firstRows:Array<Int>;
	final partnerOf:Map<Int, Int>;
	final marks = new Map<Int, Null<Array<CodeWordChange>>>();
	final original:Array<String>;
	final modified:Array<String>;

	/** The number of rows. **/
	public final count:Int;

	/** The changes the rows were made from. **/
	public final changes:Array<CodeChange>;

	/** Whether the rows are for the side-by-side layout. **/
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

	/** The line of the original at `row`, from 0, or -1 when the row has none there (a filler, or an added line). **/
	public inline function originalAt(row:Int):Int
		return data[row * STRIDE];

	/** The line of the modified text at `row`, or -1 when the row has none there. **/
	public inline function modifiedAt(row:Int):Int
		return data[row * STRIDE + 1];

	/** The index of the change `row` belongs to, or -1 for a line outside the changes. **/
	public inline function changeAt(row:Int):Int
		return data[row * STRIDE + 2];

	/** For a placeholder, how many lines it stands for; 0 for any other row. **/
	public inline function hiddenAt(row:Int):Int
		return data[row * STRIDE + 3];

	/** Where the row sits among the modified lines: its own line, or for a removed one the line an added one would have. **/
	inline function anchorAt(row:Int):Int
		return data[row * STRIDE + 4];

	public function kindAt(row:Int):CodeDiffRowKind {
		if (hiddenAt(row) > 0)
			return Placeholder;
		var o = originalAt(row), m = modifiedAt(row);
		return o >= 0 && m >= 0 ? (changeAt(row) >= 0 ? Edited : Context) : o >= 0 ? Removed : Added;
	}

	/** Whether `row` is the first of its change. **/
	public inline function firstOfChange(row:Int):Bool {
		var c = changeAt(row);
		return c >= 0 && firstRows[c] == row;
	}

	/** The row a change starts at. **/
	public inline function rowOfChange(change:Int):Int
		return firstRows[change];

	/** The text a row shows on a side of the diff: the original's line or the modified text's, null for a filler or a placeholder. **/
	public function textAt(row:Int, originalSide:Bool):Null<String> {
		if (hiddenAt(row) > 0)
			return null;
		var line = originalSide ? originalAt(row) : modifiedAt(row);
		return line < 0 ? null : originalSide ? original[line] : modified[line];
	}

	/**
		The row that shows the modified line `line`: its own row, or the placeholder that hides it, or when the text has no such
		line the row where it would come. Past the last line it is the number of rows.
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

	/** The first row at or after the original line `line`, found by looking at the rows, so it is slower than `rowOfModified`. **/
	public function rowOfOriginal(line:Int):Int {
		for (row in 0...count) {
			var o = originalAt(row);
			if (o >= line || (hiddenAt(row) > 0 && o + hiddenAt(row) > line))
				return row;
		}
		return count;
	}

	/**
		The changed words of the line at `row` on its original or modified side, as offsets into that line, or null when there
		are none to show: the line has no partner, the partner is too different, or the row is not an edit. Found when asked and kept.
	**/
	public function wordsAt(row:Int, originalSide:Bool):Null<Array<{from:Int, to:Int}>> {
		var o = originalAt(row), m = modifiedAt(row);
		if (hiddenAt(row) > 0 || changeAt(row) < 0)
			return null;
		// A line is another's partner when the pairing says so, in whichever row each of the two is.
		if (o < 0 && m >= 0) {
			var p = partnerOf.get(-m - 1);
			if (p == null)
				return null;
			o = p;
		} else if (m < 0 && o >= 0) {
			var p = partnerOf.get(o);
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
		Makes the rows of a diff. `context` is how many unchanged lines are kept on each side of a change, and the rest of a long
		run is a placeholder; a negative `context` keeps every line. A run the caller has opened, by the modified line its hidden part
		starts at (`isOpen`), is kept whole. With no changes every line is kept.
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
			var i = 0;
			while (i < pairs.length) {
				partnerOf.set(pairs[i], pairs[i + 1]);
				partnerOf.set(-pairs[i + 1] - 1, pairs[i]);
				i += 2;
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
