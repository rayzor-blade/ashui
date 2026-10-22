package ashui.components.code;

/**
	A stretch of lines that differs between two texts. Lines are counted from zero. A stretch with no lines on one side is
	a point between two lines of that text: an insertion has `originalLines` of 0, a deletion has `modifiedLines` of 0.
**/
typedef CodeChange = {
	final originalStart:Int;
	final originalLines:Int;
	final modifiedStart:Int;
	final modifiedLines:Int;
}

/** A stretch of characters that differs between two versions of one line: `from` is where it starts and `to` where it ends. **/
typedef CodeWordChange = {
	final originalFrom:Int;
	final originalTo:Int;
	final modifiedFrom:Int;
	final modifiedTo:Int;
}

/** Collects changes in the order they are found and joins the ones that touch. **/
private class Changes {
	public final list:Array<CodeChange> = [];

	public function new() {}

	public function add(originalStart:Int, originalLines:Int, modifiedStart:Int, modifiedLines:Int):Void {
		if (originalLines == 0 && modifiedLines == 0)
			return;
		var last = list.length > 0 ? list[list.length - 1] : null;
		if (last != null && last.originalStart + last.originalLines == originalStart && last.modifiedStart + last.modifiedLines == modifiedStart)
			list[list.length - 1] = {
				originalStart: last.originalStart,
				originalLines: last.originalLines + originalLines,
				modifiedStart: last.modifiedStart,
				modifiedLines: last.modifiedLines + modifiedLines
			};
		else
			list.push({originalStart: originalStart, originalLines: originalLines, modifiedStart: modifiedStart, modifiedLines: modifiedLines});
	}
}

/** Gives each distinct string a number, so comparing two of them is comparing two integers. **/
private class Interner {
	final ids = new Map<String, Int>();
	var count = 0;

	public function new() {}

	public function of(text:String):Int {
		var id = ids.get(text);
		if (id == null) {
			id = count++;
			ids.set(text, id);
		}
		return id;
	}

	public function all(texts:Array<String>):Array<Int> {
		var made = new Array<Int>();
		made.resize(texts.length);
		for (i in 0...texts.length)
			made[i] = of(texts[i]);
		return made;
	}
}

/**
	Finds what changed between two texts: which lines, and which words of an edited line. It reads no document and makes no
	element, so it can run on a worker thread, and a caller who gets its changes from elsewhere (a version-control library's
	patch) can skip `lines` and keep the rest.

	`lines` is Myers's algorithm, which finds the fewest lines changed, with two limits so a bad case is slow to refine and
	never slow to answer: the search gives up after `SEARCH` edits, and the stretch it gave up on is split at the lines that
	occur once on each side and are in the same order on both, which are also searched. A stretch with no such lines is one
	change. The changes always turn the original into the modified text; only their being the fewest is lost.
**/
class CodeDiffer {
	/** The most single-line edits Myers's search tries before it gives up on a stretch; its memory is the square of this. **/
	static inline var SEARCH = 1000;

	/** How many times a stretch that gave up is split at lines both sides have once, before it is taken as one change. **/
	static inline var DEPTH = 6;

	/** The share of a line's characters that two versions must have in common for their words to be compared. **/
	static inline var SIMILAR = 0.4;

	/** The most lines either side of a change may have for its lines to be matched by how alike they are; past it they are matched by position. **/
	static inline var MATCHING = 64;

	/** The changes that turn the lines `original` into the lines `modified`, in order, with none touching another. **/
	public static function lines(original:Array<String>, modified:Array<String>):Array<CodeChange> {
		var interner = new Interner(), a = interner.all(original), b = interner.all(modified), out = new Changes();
		range(a, 0, a.length, b, 0, b.length, out, 0);
		return out.list;
	}

	/** The lines of `text`, split at line feeds. **/
	public static inline function split(text:String):Array<String>
		return text.split("\n");

	/**
		Whether `changes` is a diff of the two: in order, inside both texts, touching nothing else, and with the same line wherever
		neither text changes. A caller checks the changes it was given before it trusts them.
	**/
	public static function valid(original:Array<String>, modified:Array<String>, changes:Array<CodeChange>):Bool {
		var o = 0, m = 0;
		for (c in changes) {
			if (c.originalLines < 0 || c.modifiedLines < 0 || (c.originalLines == 0 && c.modifiedLines == 0))
				return false;
			if (c.originalStart < o || c.modifiedStart < m)
				return false;
			// The lines between the last change and this one are the same on both sides, so they start at the same distance.
			if (c.originalStart - o != c.modifiedStart - m || c.originalStart > original.length || c.modifiedStart > modified.length)
				return false;
			for (i in 0...c.originalStart - o)
				if (original[o + i] != modified[m + i])
					return false;
			o = c.originalStart + c.originalLines;
			m = c.modifiedStart + c.modifiedLines;
			if (o > original.length || m > modified.length)
				return false;
		}
		if (original.length - o != modified.length - m)
			return false;
		for (i in 0...original.length - o)
			if (original[o + i] != modified[m + i])
				return false;
		return true;
	}

	static function range(a:Array<Int>, aFrom:Int, aTo:Int, b:Array<Int>, bFrom:Int, bTo:Int, out:Changes, depth:Int):Void {
		while (aFrom < aTo && bFrom < bTo && a[aFrom] == b[bFrom]) {
			aFrom++;
			bFrom++;
		}
		while (aFrom < aTo && bFrom < bTo && a[aTo - 1] == b[bTo - 1]) {
			aTo--;
			bTo--;
		}
		if (aFrom == aTo || bFrom == bTo) {
			out.add(aFrom, aTo - aFrom, bFrom, bTo - bFrom);
			return;
		}
		if (search(a, aFrom, aTo, b, bFrom, bTo, out))
			return;
		if (depth < DEPTH) {
			var anchors = anchorsOf(a, aFrom, aTo, b, bFrom, bTo);
			if (anchors.length > 0) {
				var ap = aFrom, bp = bFrom, i = 0;
				while (i < anchors.length) {
					range(a, ap, anchors[i], b, bp, anchors[i + 1], out, depth + 1);
					ap = anchors[i] + 1;
					bp = anchors[i + 1] + 1;
					i += 2;
				}
				range(a, ap, aTo, b, bp, bTo, out, depth + 1);
				return;
			}
		}
		out.add(aFrom, aTo - aFrom, bFrom, bTo - bFrom);
	}

	/** Myers's search over `a[aFrom...aTo]` and `b[bFrom...bTo]`, adding the changes it finds; false, adding nothing, when it needs more than `SEARCH` edits. **/
	static function search(a:Array<Int>, aFrom:Int, aTo:Int, b:Array<Int>, bFrom:Int, bTo:Int, out:Changes):Bool {
		var n = aTo - aFrom, m = bTo - bFrom, max = n + m < SEARCH ? n + m : SEARCH, offset = max + 1;
		var v = new Array<Int>();
		v.resize(2 * max + 3);
		for (i in 0...v.length)
			v[i] = 0;
		// The state before each round, for the walk back: the furthest x on each diagonal from -d - 1 to d + 1.
		var trace:Array<Array<Int>> = [];
		var found = -1;
		var d = 0;
		while (d <= max && found < 0) {
			var snapshot = new Array<Int>();
			snapshot.resize(2 * d + 3);
			for (k in 0...2 * d + 3)
				snapshot[k] = v[offset - d - 1 + k];
			trace.push(snapshot);
			var k = -d;
			while (k <= d) {
				var x = k == -d || (k != d && v[offset + k - 1] < v[offset + k + 1]) ? v[offset + k + 1] : v[offset + k - 1] + 1;
				var y = x - k;
				while (x < n && y < m && a[aFrom + x] == b[bFrom + y]) {
					x++;
					y++;
				}
				v[offset + k] = x;
				if (x >= n && y >= m) {
					found = d;
					break;
				}
				k += 2;
			}
			d++;
		}
		if (found < 0)
			return false;
		// Walk back from the end, noting each single-line edit, then add them from the start.
		var edits = new Array<Int>();
		var x = n, y = m;
		d = found;
		while (d > 0) {
			var snapshot = trace[d], k = x - y;
			var down = k == -d || (k != d && snapshot[k - 1 + d + 1] < snapshot[k + 1 + d + 1]);
			var previousK = down ? k + 1 : k - 1;
			var previousX = snapshot[previousK + d + 1], previousY = previousX - previousK;
			// Down is a line of `b` added, right is a line of `a` removed.
			edits.push(previousX);
			edits.push(previousY);
			edits.push(down ? 1 : 0);
			x = previousX;
			y = previousY;
			d--;
		}
		var i = edits.length - 3;
		while (i >= 0) {
			if (edits[i + 2] == 1)
				out.add(aFrom + edits[i], 0, bFrom + edits[i + 1], 1);
			else
				out.add(aFrom + edits[i], 1, bFrom + edits[i + 1], 0);
			i -= 3;
		}
		return true;
	}

	/**
		The lines that occur once in `a[aFrom...aTo]` and once in `b[bFrom...bTo]` and keep their order, as pairs of indices
		(`a`'s then `b`'s) in one flat array: the longest such run, found by patience sorting.
	**/
	static function anchorsOf(a:Array<Int>, aFrom:Int, aTo:Int, b:Array<Int>, bFrom:Int, bTo:Int):Array<Int> {
		var inA = new Map<Int, Int>(), inB = new Map<Int, Int>(), at = new Map<Int, Int>();
		for (i in aFrom...aTo)
			inA.set(a[i], (inA.exists(a[i]) ? inA.get(a[i]) : 0) + 1);
		for (j in bFrom...bTo) {
			inB.set(b[j], (inB.exists(b[j]) ? inB.get(b[j]) : 0) + 1);
			at.set(b[j], j);
		}
		// The unique lines in the order of `a`, as pairs; their `b` indices are what has to increase.
		var ai = new Array<Int>(), bi = new Array<Int>();
		for (i in aFrom...aTo)
			if (inA.get(a[i]) == 1 && inB.get(a[i]) == 1) {
				ai.push(i);
				bi.push(at.get(a[i]));
			}
		if (ai.length == 0)
			return [];
		// tails[l] is the index of the last element of the best run of length l + 1; before[e] links a run back.
		var tails = new Array<Int>(), before = new Array<Int>();
		before.resize(ai.length);
		for (e in 0...ai.length) {
			var low = 0, high = tails.length;
			while (low < high) {
				var middle = (low + high) >> 1;
				if (bi[tails[middle]] < bi[e])
					low = middle + 1;
				else
					high = middle;
			}
			before[e] = low > 0 ? tails[low - 1] : -1;
			if (low == tails.length)
				tails.push(e);
			else
				tails[low] = e;
		}
		var run = new Array<Int>(), e = tails[tails.length - 1];
		while (e >= 0) {
			run.push(bi[e]);
			run.push(ai[e]);
			e = before[e];
		}
		var anchors = new Array<Int>(), i = run.length - 2;
		while (i >= 0) {
			anchors.push(run[i + 1]);
			anchors.push(run[i]);
			i -= 2;
		}
		return anchors;
	}

	// ---- Words ----

	/** The start of each token of `text` and its end at the last place: words, runs of white space, and each other character. **/
	static function tokens(text:String, ids:Interner, into:Array<Int>):Array<Int> {
		var starts = new Array<Int>(), i = 0, n = text.length;
		while (i < n) {
			starts.push(i);
			var c = StringTools.fastCodeAt(text, i), from = i;
			if (isWord(c))
				while (i < n && isWord(StringTools.fastCodeAt(text, i)))
					i++;
			else if (c == " ".code || c == "\t".code)
				while (i < n && (StringTools.fastCodeAt(text, i) == " ".code || StringTools.fastCodeAt(text, i) == "\t".code))
					i++;
			else
				i++;
			into.push(ids.of(text.substring(from, i)));
		}
		starts.push(n);
		return starts;
	}

	static inline function isWord(c:Int):Bool
		return c == "_".code || c == "$".code || (c >= "0".code && c <= "9".code) || (c >= "a".code && c <= "z".code) || (c >= "A".code && c <= "Z".code) || c > 127;

	static inline function isSpace(c:Int):Bool
		return c == " ".code || c == "\t".code;

	/**
		The words that differ between two versions of a line, or null when the versions have too little in common for the marks
		to help (a rewritten line is better shown whole). Neighbouring changes with only white space between them are one.
	**/
	public static function words(original:String, modified:String):Null<Array<CodeWordChange>> {
		if (original == modified)
			return [];
		var ids = new Interner(), a = new Array<Int>(), b = new Array<Int>();
		var aStarts = tokens(original, ids, a), bStarts = tokens(modified, ids, b), out = new Changes();
		range(a, 0, a.length, b, 0, b.length, out, 0);
		// The characters outside every change are the ones the two share.
		var kept = 0, ap = 0;
		for (c in out.list) {
			kept += countKept(original, aStarts[ap], aStarts[c.originalStart]);
			ap = c.originalStart + c.originalLines;
		}
		kept += countKept(original, aStarts[ap], original.length);
		var longest = Std.int(Math.max(nonSpace(original), nonSpace(modified)));
		if (longest == 0 || kept < longest * SIMILAR)
			return null;
		var merged:Array<CodeWordChange> = [];
		for (c in out.list) {
			var word:CodeWordChange = {
				originalFrom: aStarts[c.originalStart],
				originalTo: aStarts[c.originalStart + c.originalLines],
				modifiedFrom: bStarts[c.modifiedStart],
				modifiedTo: bStarts[c.modifiedStart + c.modifiedLines]
			};
			var last = merged.length > 0 ? merged[merged.length - 1] : null;
			if (last != null && onlySpace(original, last.originalTo, word.originalFrom))
				merged[merged.length - 1] = {
					originalFrom: last.originalFrom,
					originalTo: word.originalTo,
					modifiedFrom: last.modifiedFrom,
					modifiedTo: word.modifiedTo
				};
			else
				merged.push(word);
		}
		return merged;
	}

	static function countKept(text:String, from:Int, to:Int):Int {
		var n = 0;
		for (i in from...to)
			if (!isSpace(StringTools.fastCodeAt(text, i)))
				n++;
		return n;
	}

	static function nonSpace(text:String):Int
		return countKept(text, 0, text.length);

	static function onlySpace(text:String, from:Int, to:Int):Bool {
		for (i in from...to)
			if (!isSpace(StringTools.fastCodeAt(text, i)))
				return false;
		return true;
	}

	// ---- Pairing ----

	/**
		Which removed line of `change` and which added line are the same line edited, as pairs of indices into `original` and
		`modified` in one flat array, both rising. When the two sides have as many lines each takes the one in its own place; when
		not, lines are matched by how alike they are, so an insertion among edited lines does not shift the pairs, and a line
		with no likeness is left out. A change too large to compare by likeness pairs nothing unless its sides are equal in size.
	**/
	public static function pairs(original:Array<String>, modified:Array<String>, change:CodeChange):Array<Int> {
		var n = change.originalLines, m = change.modifiedLines, result = new Array<Int>();
		if (n == 0 || m == 0)
			return result;
		if (n == m) {
			for (i in 0...n) {
				result.push(change.originalStart + i);
				result.push(change.modifiedStart + i);
			}
			return result;
		}
		if (n > MATCHING || m > MATCHING)
			return result;
		// A line as a bag of its words and marks, white space left out, with how many characters they come to.
		var ids = new Interner(), bags:Array<Map<Int, Int>> = [], sizes = new Array<Int>(), lengths = new Map<Int, Int>();
		function bagOf(text:String):Int {
			var list = new Array<Int>(), starts = tokens(text, ids, list), bag = new Map<Int, Int>(), size = 0;
			for (t in 0...list.length) {
				var length = starts[t + 1] - starts[t];
				if (isSpace(StringTools.fastCodeAt(text, starts[t])))
					continue;
				bag.set(list[t], (bag.exists(list[t]) ? bag.get(list[t]) : 0) + 1);
				lengths.set(list[t], length);
				size += length;
			}
			bags.push(bag);
			sizes.push(size);
			return bags.length - 1;
		}
		var oldBags = [for (i in 0...n) bagOf(original[change.originalStart + i])];
		var newBags = [for (j in 0...m) bagOf(modified[change.modifiedStart + j])];
		var score = new Array<Float>();
		score.resize(n * m);
		for (i in 0...n)
			for (j in 0...m) {
				var x = bags[oldBags[i]], y = bags[newBags[j]], common = 0;
				for (t => count in x)
					if (y.exists(t))
						common += Std.int(Math.min(count, y.get(t))) * lengths.get(t);
				var longest = Std.int(Math.max(sizes[oldBags[i]], sizes[newBags[j]]));
				var like = longest == 0 ? 0.0 : common / longest;
				score[i * m + j] = like >= SIMILAR ? like : -1.0;
			}
		// The best total likeness of a matching that keeps order, over the first i old lines and the first j new ones.
		var best = new Array<Float>();
		best.resize((n + 1) * (m + 1));
		for (i in 0...(n + 1) * (m + 1))
			best[i] = 0.0;
		for (i in 1...n + 1)
			for (j in 1...m + 1) {
				var here = Math.max(best[(i - 1) * (m + 1) + j], best[i * (m + 1) + j - 1]);
				var s = score[(i - 1) * m + j - 1];
				if (s >= 0)
					here = Math.max(here, best[(i - 1) * (m + 1) + j - 1] + s);
				best[i * (m + 1) + j] = here;
			}
		var i = n, j = m, found = new Array<Int>();
		while (i > 0 && j > 0) {
			var s = score[(i - 1) * m + j - 1];
			if (s >= 0 && best[i * (m + 1) + j] == best[(i - 1) * (m + 1) + j - 1] + s) {
				found.push(change.modifiedStart + j - 1);
				found.push(change.originalStart + i - 1);
				i--;
				j--;
			} else if (best[i * (m + 1) + j] == best[(i - 1) * (m + 1) + j])
				i--;
			else
				j--;
		}
		var k = found.length - 2;
		while (k >= 0) {
			result.push(found[k + 1]);
			result.push(found[k]);
			k -= 2;
		}
		return result;
	}
}
