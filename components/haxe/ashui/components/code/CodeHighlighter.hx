package ashui.components.code;

/** CSS token names, deliberately independent of a color scheme (e53597f). **/
enum abstract CodeTokenKind(String) to String {
	var Plain = "plain";
	var Keyword = "keyword";
	var StringLiteral = "string";
	var Comment = "comment";
	var Number = "number";
	var Type = "type";
	var Function = "function";
	var Operator = "operator";
}

typedef CodeToken = {final from:Int; final to:Int; final kind:CodeTokenKind;}
typedef CodeHighlight = {final tokens:Array<CodeToken>; final state:String;}

/**
	A line highlighter. Offsets are Haxe string indices, not UTF-8 bytes.
	Return the lexical state to pass to the next line, including for blank
	lines. Unchanged lines are reused when this state is unchanged. Emit
	Comment and StringLiteral tokens so folding ignores their brackets.
**/
interface CodeHighlighter {
	public function highlight(line:String, state:String):CodeHighlight;
}
