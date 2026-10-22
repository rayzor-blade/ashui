import ashui.components.code.CodeDiffRows;
import ashui.components.code.CodeDiffer;

/** The rows of a diff show every line of both texts once and in order, line up in the side-by-side layout, and collapse long runs. **/
class CodeDiffRowsCheck {
	static var checks = 0;

	static function check(name:String, ok:Bool, ?detail:Dynamic):Void {
		if (!ok)
			throw name + (detail == null ? "" : ' ($detail)');
		checks++;
		Sys.println('ok   $name');
	}

	static var seed = 424242;

	static function next(n:Int):Int {
		seed = (seed * 1103515245 + 12345) & 0x7fffffff;
		return (seed >> 8) % n;
	}

	static function rowsOf(a:Array<String>, b:Array<String>, split:Bool, context:Int, ?open:Int->Bool):CodeDiffRows
		return CodeDiffRows.build(a, b, CodeDiffer.lines(a, b), split, context, open);

	/** What is wrong with the rows, or null: each line of each text once and in order, equal lines where neither changed. **/
	static function wrong(a:Array<String>, b:Array<String>, rows:CodeDiffRows, context:Int):Null<String> {
		var nextO = 0, nextM = 0;
		for (r in 0...rows.count) {
			var o = rows.originalAt(r), m = rows.modifiedAt(r), hidden = rows.hiddenAt(r);
			if (o >= 0) {
				if (o != nextO)
					return 'row $r: original line $o, expected $nextO';
				nextO += hidden > 0 ? hidden : 1;
			}
			if (m >= 0) {
				if (m != nextM)
					return 'row $r: modified line $m, expected $nextM';
				nextM += hidden > 0 ? hidden : 1;
			}
			if (hidden > 0 && (o < 0 || m < 0 || context < 0 || rows.changeAt(r) >= 0))
				return 'row $r: a placeholder that is not one';
			if (o >= 0 && m >= 0 && hidden == 0 && rows.changeAt(r) < 0 && a[o] != b[m])
				return 'row $r: context lines differ';
		}
		if (nextO != a.length || nextM != b.length)
			return 'covered $nextO of ${a.length} and $nextM of ${b.length}';
		var firsts = 0;
		for (r in 0...rows.count)
			if (rows.firstOfChange(r))
				firsts++;
		if (firsts != rows.changes.length)
			return 'first rows $firsts of ${rows.changes.length} changes';
		for (c in 0...rows.changes.length)
			if (rows.changeAt(rows.rowOfChange(c)) != c || (rows.rowOfChange(c) > 0 && rows.changeAt(rows.rowOfChange(c) - 1) == c))
				return 'change $c does not start at its row';
		return null;
	}

	static function lines(text:String):Array<String>
		return CodeDiffer.split(text);

	static function main():Void {
		var a = lines("a\nb\nc\nd"), b = lines("a\nB\nc\nd");
		var stacked = rowsOf(a, b, false, -1);
		check("inline, a replaced line is a removed row then an added row", stacked.count == 5 && stacked.kindAt(1) == Removed && stacked.kindAt(2) == Added && stacked.kindAt(0) == Context, [for (i in 0...stacked.count) stacked.kindAt(i)]);
		check("the removed row has only an original line, the added one only a modified line", stacked.originalAt(1) == 1 && stacked.modifiedAt(1) == -1 && stacked.originalAt(2) == -1 && stacked.modifiedAt(2) == 1);
		var side = rowsOf(a, b, true, -1);
		check("side by side, they share a row", side.count == 4 && side.kindAt(1) == Edited && side.originalAt(1) == 1 && side.modifiedAt(1) == 1);
		var uneven = rowsOf(lines("a\nb\nc\nd\ne"), lines("a\nX\nY\nZ\ne"), true, -1);
		check("side by side, three lines for three share three rows", uneven.count == 5 && uneven.kindAt(1) == Edited && uneven.kindAt(3) == Edited);
		var more = rowsOf(lines("a\nold\ne"), lines("a\nx1\nx2\nx3\ne"), true, -1);
		check("side by side, an insertion more than the deletion leaves fillers opposite", more.count == 5 && more.originalAt(3) == -1 && more.modifiedAt(3) == 3 && more.kindAt(3) == Added, [for (i in 0...more.count) more.originalAt(i) + ":" + more.modifiedAt(i)]);

		var long = [for (i in 0...100) 'line $i'], edited = long.copy();
		edited[50] = "changed";
		var folded = rowsOf(long, edited, false, 3);
		check("a change in the middle of a hundred lines is two rows between a placeholder and three lines of context on each side", folded.count == 10, folded.count);
		check("and the rows account for every line", wrong(long, edited, folded, 3) == null, wrong(long, edited, folded, 3));
		var placeholders = [for (r in 0...folded.count) if (folded.kindAt(r) == Placeholder) folded.hiddenAt(r)];
		check("the placeholders hide the lines the context leaves out", placeholders.length == 2 && placeholders[0] == 47 && placeholders[1] == 46, placeholders);
		var open = rowsOf(long, edited, false, 3, line -> line == 0);
		check("a run the caller opened, by the line its hidden part starts at, is shown whole", open.count == 56, [open.count, folded.count]);
		check("and the other stays a placeholder", [for (r in 0...open.count) if (open.kindAt(r) == Placeholder) 1].length == 1);
		var everything = rowsOf(long, edited, false, -1);
		check("a negative context keeps every line", everything.count == 101 && wrong(long, edited, everything, -1) == null);
		var none = rowsOf(long, long, false, 3);
		check("texts that are the same keep every line, as context", none.count == 100 && none.kindAt(0) == Context && none.changes.length == 0);
		var near = rowsOf(lines("1\n2\n3\n4\n5\n6\n7\n8\n9\n10"), lines("1\n2\n3\n4\nX\n6\n7\n8\n9\n10"), false, 3);
		check("a run only one or two lines past the context is shown, not hidden", [for (r in 0...near.count) if (near.kindAt(r) == Placeholder) 1].length == 0 && near.count == 11, near.count);

		// Words and navigation.
		var words = rowsOf(lines("x\nlet total = price * count;\ny"), lines("x\nlet total = price * quantity;\ny"), false, -1);
		var wordsRemoved = words.wordsAt(1, true), wordsAdded = words.wordsAt(2, false);
		check("the changed word is marked on the removed line and on the added one", wordsRemoved != null && wordsAdded != null && "let total = price * count;".substring(wordsRemoved[0].from, wordsRemoved[0].to) == "count" && "let total = price * quantity;".substring(wordsAdded[0].from, wordsAdded[0].to) == "quantity");
		check("a context row has no word marks", words.wordsAt(0, false) == null);
		var split = rowsOf(lines("x\nlet total = price * count;\ny"), lines("x\nlet total = price * quantity;\ny"), true, -1);
		check("side by side, the shared row marks both of its sides", split.wordsAt(1, true) != null && split.wordsAt(1, false) != null);
		check("modified lines are found in the rows", folded.rowOfModified(50) < folded.count && folded.modifiedAt(folded.rowOfModified(50)) == 50);
		check("a hidden line is found at the placeholder that hides it", folded.hiddenAt(folded.rowOfModified(10)) > 0);
		check("a line past the end is the number of rows", folded.rowOfModified(500) == folded.count);

		// Random pairs of texts, both layouts, several contexts.
		var worst:Null<String> = null;
		for (round in 0...600) {
			var x = [for (_ in 0...next(30)) 'l${next(6)}'], y = [for (_ in 0...next(30)) 'l${next(6)}'];
			for (split in [false, true])
				for (context in [-1, 0, 1, 3]) {
					var rows = rowsOf(x, y, split, context);
					var problem = wrong(x, y, rows, context);
					if (problem != null && worst == null)
						worst = 'split=$split context=$context: $problem; ${x.join(",")} / ${y.join(",")}';
				}
		}
		check("six hundred random pairs show every line once in order, in both layouts and with each context", worst == null, worst);

		// A large file.
		var big = [for (i in 0...50000) 'line $i with text'], bigEdited = big.copy();
		for (i in 0...200)
			bigEdited[i * 250] = 'changed $i';
		var t0 = haxe.Timer.stamp();
		var bigRows = rowsOf(big, bigEdited, true, 3);
		var took = haxe.Timer.stamp() - t0;
		check("fifty thousand lines with two hundred edits make their rows", wrong(big, bigEdited, bigRows, 3) == null && bigRows.changes.length == 200);
		check("and quickly", took < 2.0, took);
		Sys.println('$checks checks: ALL PASSED');
	}
}
