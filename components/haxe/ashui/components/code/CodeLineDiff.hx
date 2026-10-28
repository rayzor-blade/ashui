package ashui.components.code;

/** Source line boundaries, excluding the line break. **/
private typedef Span = {start:Int, end:Int};

/**
	Maps source lines through a replaced text region.
	Shared lines keep their corresponding positions. Lines between shared
	anchors map by position within the gap; lines without a destination
	are omitted. This preserves line-based state across file reloads as
	well as local edits.
**/
class CodeLineDiff {
	/** Maximum changed-line count for line mapping. Larger changes skip comparison. **/
	static inline var LIMIT = 400;

	final oldLines:Array<Span>;
	final newLines:Array<Span>;
	final pair:Array<Int>;

	function new(oldLines:Array<Span>, newLines:Array<Span>, pair:Array<Int>) {
		this.oldLines = oldLines;
		this.newLines = newLines;
		this.pair = pair;
	}

	/**
		Compares complete lines inside the replaced regions of `before` and
		`after`. Returns null when there are no complete lines or too many changes.
	**/
	public static function of(before:String, after:String, start:Int, oldEnd:Int, newEnd:Int):Null<CodeLineDiff> {
		var oldLines = wholeLines(before, start, oldEnd), newLines = wholeLines(after, start, newEnd);
		if (oldLines.length == 0 || newLines.length == 0)
			return null;
		var matched = match([for (l in oldLines) before.substring(l.start, l.end)], [for (l in newLines) after.substring(l.start, l.end)]);
		return matched == null ? null : new CodeLineDiff(oldLines, newLines, pairGaps(matched, newLines.length));
	}

	/** Maps an old source offset to the new text, or -1 when its line has no destination. **/
	public function map(offset:Int):Int {
		for (i in 0...oldLines.length) {
			var line = oldLines[i];
			if (offset < line.start)
				break;
			if (offset <= line.end) {
				var to = pair[i];
				if (to < 0)
					return -1;
				var target = newLines[to];
				return target.start + Std.int(Math.min(offset - line.start, target.end - target.start));
			}
		}
		return -1;
	}

	/** Returns complete lines within the specified text range. **/
	static function wholeLines(text:String, from:Int, to:Int):Array<Span> {
		var lines = [], at = from;
		// A first line that starts before `from` is cut by it.
		if (at > 0 && text.charCodeAt(at - 1) != "\n".code) {
			var next = text.indexOf("\n", at);
			if (next < 0 || next >= to)
				return lines;
			at = next + 1;
		}
		while (at <= to) {
			var end = text.indexOf("\n", at);
			if (end < 0)
				end = text.length;
			// A last line that goes on past `to` is cut by it.
			if (end > to)
				break;
			lines.push({start: at, end: end});
			at = end + 1;
		}
		return lines;
	}

	/**
		Maps original lines to equal modified lines in a shortest edit sequence.
		Unmatched lines use -1; returns null if more than `LIMIT` lines change.
	**/
	static function match(a:Array<String>, b:Array<String>):Null<Array<Int>> {
		var n = a.length, m = b.length, result = [for (_ in a) -1];
		var limit = Std.int(Math.min(n + m, LIMIT)), shift = limit + 1;
		var v = [for (_ in 0...2 * limit + 3) 0], trace:Array<Array<Int>> = [], found = -1;
		for (d in 0...limit + 1) {
			trace.push(v.copy());
			var k = -d;
			while (k <= d) {
				var x = k == -d || (k != d && v[shift + k - 1] < v[shift + k + 1]) ? v[shift + k + 1] : v[shift + k - 1] + 1, y = x - k;
				while (x < n && y < m && a[x] == b[y]) {
					x++;
					y++;
				}
				v[shift + k] = x;
				if (x >= n && y >= m) {
					found = d;
					break;
				}
				k += 2;
			}
			if (found >= 0)
				break;
		}
		if (found < 0)
			return null;
		var x = n, y = m, d = found;
		while (d > 0) {
			var before = trace[d], k = x - y;
			var previous = k == -d || (k != d && before[shift + k - 1] < before[shift + k + 1]) ? k + 1 : k - 1;
			var px = before[shift + previous], py = px - previous;
			while (x > px && y > py) {
				x--;
				y--;
				result[x] = y;
			}
			x = px;
			y = py;
			d--;
		}
		while (x > 0 && y > 0) {
			x--;
			y--;
			result[x] = y;
		}
		return result;
	}

	/** Pairs lines between shared anchors by position. Extra old lines map to the final new line in the gap. **/
	static function pairGaps(matched:Array<Int>, newCount:Int):Array<Int> {
		var pair = matched.copy(), lowest = 0, taken = 0;
		for (i in 0...matched.length) {
			if (matched[i] >= 0) {
				lowest = matched[i] + 1;
				taken = 0;
				continue;
			}
			var next = newCount;
			for (j in i + 1...matched.length)
				if (matched[j] >= 0) {
					next = matched[j];
					break;
				}
			var candidate = Std.int(Math.min(lowest + taken, next - 1));
			pair[i] = candidate >= lowest ? candidate : -1;
			taken++;
		}
		return pair;
	}
}
