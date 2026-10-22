import ashui.components.code.CodeDiffer;
import ashui.components.code.CodeDiffer.CodeChange;

/** The line diff is a valid one and a smallest one on small inputs, stays valid and quick on large ones, and finds the words and pairs the rows use. **/
class CodeDiffEngine {
	static var checks = 0;

	static function check(name:String, ok:Bool, ?detail:Dynamic):Void {
		if (!ok)
			throw name + (detail == null ? "" : ' ($detail)');
		checks++;
		Sys.println('ok   $name');
	}

	static var seed = 987654321;

	static function next(n:Int):Int {
		seed = (seed * 1103515245 + 12345) & 0x7fffffff;
		return (seed >> 8) % n;
	}

	/** The length of the longest common subsequence, by the table. **/
	static function lcs(a:Array<String>, b:Array<String>):Int {
		var row = [for (_ in 0...b.length + 1) 0];
		for (i in 1...a.length + 1) {
			var diagonal = 0;
			for (j in 1...b.length + 1) {
				var above = row[j];
				row[j] = a[i - 1] == b[j - 1] ? diagonal + 1 : Std.int(Math.max(row[j], row[j - 1]));
				diagonal = above;
			}
		}
		return row[b.length];
	}

	static function changed(changes:Array<CodeChange>):Int {
		var n = 0;
		for (c in changes)
			n += c.originalLines + c.modifiedLines;
		return n;
	}

	static function lines(text:String):Array<String>
		return CodeDiffer.split(text);

	static function main():Void {
		check("identical texts have no changes", CodeDiffer.lines(lines("a\nb\nc"), lines("a\nb\nc")).length == 0);
		var insert = CodeDiffer.lines(lines("a\nb\nc"), lines("a\nb\nx\nc"));
		check("an insertion is one change with no original lines", insert.length == 1 && insert[0].originalLines == 0 && insert[0].modifiedStart == 2 && insert[0].modifiedLines == 1, insert);
		var delete = CodeDiffer.lines(lines("a\nb\nc"), lines("a\nc"));
		check("a deletion is one change with no modified lines", delete.length == 1 && delete[0].originalStart == 1 && delete[0].originalLines == 1 && delete[0].modifiedLines == 0, delete);
		var replace = CodeDiffer.lines(lines("a\nb\nc"), lines("a\nx\nc"));
		check("a replaced line is one change of one line each way", replace.length == 1 && replace[0].originalLines == 1 && replace[0].modifiedLines == 1, replace);
		var apart = CodeDiffer.lines(lines("a\nb\nc\nd\ne\nf"), lines("a\nB\nc\nd\ne\nF"));
		check("changes apart are two", apart.length == 2 && apart[0].originalStart == 1 && apart[1].originalStart == 5, apart);
		check("an empty text against some lines is one insertion", CodeDiffer.lines([], ["a", "b"]).length == 1 && CodeDiffer.lines(["a", "b"], []).length == 1);

		// Valid and smallest, over many random small texts from a small alphabet, so lines repeat as in code.
		var worst:Dynamic = null;
		for (round in 0...3000) {
			var a = [for (_ in 0...next(14)) String.fromCharCode("a".code + next(4))];
			var b = [for (_ in 0...next(14)) String.fromCharCode("a".code + next(4))];
			var changes = CodeDiffer.lines(a, b);
			if (!CodeDiffer.valid(a, b, changes) || changed(changes) != a.length + b.length - 2 * lcs(a, b)) {
				worst = {a: a.join(""), b: b.join(""), changes: changes};
				break;
			}
			for (i in 1...changes.length)
				if (changes[i - 1].originalStart + changes[i - 1].originalLines == changes[i].originalStart && changes[i - 1].modifiedStart + changes[i - 1].modifiedLines == changes[i].modifiedStart)
					worst = {a: a.join(""), b: b.join(""), touching: i};
			if (worst != null)
				break;
		}
		check("three thousand random pairs give valid, smallest changes that touch nothing", worst == null, worst);

		// Supplied changes are checked before they are trusted.
		var base = lines("a\nb\nc\nd");
		check("a diff of the texts is valid", CodeDiffer.valid(base, lines("a\nB\nc\nd"), [{originalStart: 1, originalLines: 1, modifiedStart: 1, modifiedLines: 1}]));
		check("a change that leaves a difference out is not valid", !CodeDiffer.valid(base, lines("a\nB\nC\nd"), [{originalStart: 1, originalLines: 1, modifiedStart: 1, modifiedLines: 1}]));
		check("a change past the end is not valid", !CodeDiffer.valid(base, lines("a\nb\nc\nd"), [{originalStart: 9, originalLines: 1, modifiedStart: 9, modifiedLines: 1}]));
		check("changes out of order are not valid", !CodeDiffer.valid(base, lines("A\nb\nC\nd"), [
			{originalStart: 2, originalLines: 1, modifiedStart: 2, modifiedLines: 1},
			{originalStart: 0, originalLines: 1, modifiedStart: 0, modifiedLines: 1}
		]));

		// A large file with a few edits is quick, and its changes are where the edits are.
		var big = [for (i in 0...60000) 'line $i of the file, with some text in it'];
		var edited = big.copy();
		edited[100] = "changed 100";
		edited.splice(30000, 3);
		edited.insert(45000, "added one");
		edited.insert(45000, "added two");
		var t0 = haxe.Timer.stamp();
		var found = CodeDiffer.lines(big, edited);
		var took = haxe.Timer.stamp() - t0;
		check("sixty thousand lines with four edits give three changes", found.length == 3 && CodeDiffer.valid(big, edited, found), found);
		check("and take well under a second", took < 1.0, took);

		// Past the search limit: the answer stays valid and comes quickly, through the lines that occur once.
		var many = [for (i in 0...6000) 'row $i'];
		var scrambled = many.copy();
		for (i in 0...scrambled.length)
			if (i % 2 == 0)
				scrambled[i] = 'new ${i}';
		var t1 = haxe.Timer.stamp();
		var far = CodeDiffer.lines(many, scrambled);
		var farTook = haxe.Timer.stamp() - t1;
		check("three thousand edits in six thousand lines are valid", CodeDiffer.valid(many, scrambled, far));
		check("and cost three thousand changes, as the smallest does", changed(far) == 6000, changed(far));
		check("and are quick", farTook < 3.0, farTook);
		var shuffled = many.copy();
		for (i in 0...shuffled.length) {
			var j = next(shuffled.length), x = shuffled[i];
			shuffled[i] = shuffled[j];
			shuffled[j] = x;
		}
		var t2 = haxe.Timer.stamp();
		var mixed = CodeDiffer.lines(many, shuffled);
		check("six thousand lines in a random order are valid", CodeDiffer.valid(many, shuffled, mixed));
		check("and are quick", haxe.Timer.stamp() - t2 < 3.0, haxe.Timer.stamp() - t2);

		// Words.
		var w = CodeDiffer.words("let x = foo(a, b);", "let x = foo(a, c, b);");
		check("a word added is one change, in both lines", w != null && w.length == 1 && "let x = foo(a, b);".substring(w[0].originalFrom, w[0].originalTo) == "" && "let x = foo(a, c, b);".substring(w[0].modifiedFrom, w[0].modifiedTo) == "c, ", w);
		var w2 = CodeDiffer.words("return value;", "return other;");
		check("a word replaced is marked on both sides", w2 != null && w2.length == 1 && "return value;".substring(w2[0].originalFrom, w2[0].originalTo) == "value" && "return other;".substring(w2[0].modifiedFrom, w2[0].modifiedTo) == "other", w2);
		var w3 = CodeDiffer.words("alpha beta gamma delta", "ALPHA beta gamma DELTA");
		check("changes with kept words between are two", w3 != null && w3.length == 2, w3);
		var w4 = CodeDiffer.words("the quick brown fox jumps", "the QUICK BROWN fox jumps");
		check("changes with only white space between are one", w4 != null && w4.length == 1 && "the quick brown fox jumps".substring(w4[0].originalFrom, w4[0].originalTo) == "quick brown", w4);
		check("a line with too little kept has no marks", CodeDiffer.words("a b c", "x b y") == null);
		check("lines with little in common have no word marks", CodeDiffer.words("function render(props) {", "totally different content here") == null);
		check("equal lines have no changes", CodeDiffer.words("same", "same").length == 0);
		check("tabs and spaces are white space", CodeDiffer.words("\tfoo()", "    foo()") != null);

		// Pairs.
		var before = lines("foo(1)\nbar(2)\nbaz(3)\nend"), after = lines("foo(10)\nbaz(30)\nend");
		var changes = CodeDiffer.lines(before, after);
		check("edited lines among others make one change", changes.length == 1 && changes[0].originalLines == 3 && changes[0].modifiedLines == 2, changes);
		var pairs = CodeDiffer.pairs(before, after, changes[0]);
		check("a deleted line between two edited ones does not move the pairs", pairs.length == 4 && pairs[0] == 0 && pairs[1] == 0 && pairs[2] == 2 && pairs[3] == 1, pairs);
		var equalSides = CodeDiffer.pairs(["a", "b"], ["c", "d"], {originalStart: 0, originalLines: 2, modifiedStart: 0, modifiedLines: 2});
		check("sides of equal size pair by position", equalSides.join(",") == "0,0,1,1", equalSides);
		check("a side with no lines has no pairs", CodeDiffer.pairs([], ["a"], {originalStart: 0, originalLines: 0, modifiedStart: 0, modifiedLines: 1}).length == 0);
		var unlike = CodeDiffer.pairs(["alpha beta gamma"], ["x", "y"], {originalStart: 0, originalLines: 1, modifiedStart: 0, modifiedLines: 2});
		check("lines with no likeness are not paired when sides differ in size", unlike.length == 0, unlike);
		Sys.println('$checks checks: ALL PASSED');
	}
}
