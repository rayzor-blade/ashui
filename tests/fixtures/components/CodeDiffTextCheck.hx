import ashui.components.code.CodeDiffText;
import ashui.components.code.CodeDocument;
import ashui.components.code.CodeSyntax;

/** Lines coloured as rows ask for them come out as a document colours them whole, in any order, and a very long line is cut. **/
class CodeDiffTextCheck {
	static var checks = 0;

	static function check(name:String, ok:Bool, ?detail:Dynamic):Void {
		if (!ok)
			throw name + (detail == null ? "" : ' ($detail)');
		checks++;
		Sys.println('ok   $name');
	}

	static var seed = 20261022;

	static function next(n:Int):Int {
		seed = (seed * 1103515245 + 12345) & 0x7fffffff;
		return (seed >> 8) % n;
	}

	static function kinds(line:CodeLine):String
		return [for (t in 0...line.tokenCount) line.tokenKind(t)].join(",");

	static function main():Void {
		var syntax = CodeSyntax.forLanguage("haxe");
		// Block comments that span many lines, so a line's colours depend on lines far before it.
		var lines = [for (i in 0...6000) i % 700 == 100 ? '/* a long comment $i' : i % 700 == 400 ? 'its end $i */ var after$i = 1;' : 'var x$i = "text $i"; // note'];
		var oracle = new CodeDocument(lines.join("\n"), syntax);
		var text = new CodeDiffText(syntax);
		text.reset(lines, syntax);
		var wrong = null;
		for (_ in 0...400) {
			var i = next(lines.length);
			if (kinds(text.line(i)) != kinds(oracle.lines[i])) {
				wrong = 'line $i: ${kinds(text.line(i))} against ${kinds(oracle.lines[i])}';
				break;
			}
		}
		check("lines asked for in a random order are coloured as the document colours them", wrong == null, wrong);
		check("a line inside a comment that began far above it is a comment", kinds(text.line(250)) == "comment", kinds(text.line(250)));
		check("and the line that ends the comment goes on with code", text.line(401).tokenCount > 0 && kinds(text.line(401)).indexOf("keyword") >= 0, kinds(text.line(401)));
		var sequential = null;
		text.reset(lines, syntax);
		for (i in 0...lines.length)
			if (kinds(text.line(i)) != kinds(oracle.lines[i])) {
				sequential = 'line $i';
				break;
			}
		check("all the lines in order, past the number it keeps, are coloured as the document colours them", sequential == null, sequential);
		text.reset(lines, syntax);
		var rounds = 0;
		while (!text.fill(500) && rounds < 100)
			rounds++;
		check("the checkpoints are made a slice at a time", rounds > 3 && rounds < 100, rounds);
		var after = null;
		for (_ in 0...300) {
			var i = next(lines.length);
			if (kinds(text.line(i)) != kinds(oracle.lines[i])) {
				after = 'line $i';
				break;
			}
		}
		check("and lines found from them are the same", after == null, after);

		// Another text and another set of lines.
		text.reset(["plain", "lines"], syntax);
		check("resetting makes the lines the new text's", text.length == 2 && text.line(1).text == "lines");
		check("a line there is not gives an empty one", text.line(5).text == "" && text.line(-1).text == "");
		text.reset([], syntax);
		check("no lines is one empty line", text.length == 1 && text.line(0).text == "");

		// A very long line is cut, with a mark that it was.
		var long = [for (_ in 0...5000) "x"].join("");
		text.reset(["short", long, "after"], syntax);
		var cut = text.line(1);
		check("a line past the limit is shown cut, with an ellipsis", cut.text.length == CodeDiffText.CLIP + 1 && StringTools.endsWith(cut.text, "…"), cut.text.length);
		check("and its ellipsis is a token, so it is drawn", cut.tokenCount > 0 && cut.tokenTo(cut.tokenCount - 1) == CodeDiffText.CLIP + 1, cut.tokenCount);
		check("the lines after it are as they were", text.line(2).text == "after");
		Sys.println('$checks checks: ALL PASSED');
	}
}
