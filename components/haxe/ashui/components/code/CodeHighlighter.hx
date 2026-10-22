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
	var Tag = "tag";
	var Attribute = "attribute";
	var MarkupText = "markup-text";
}

/** Optional inline CSS values for formatted text. Editors render them only with tokenStyles enabled. **/
typedef CodeTokenStyle = {
	?color:String,
	?background:String,
	?fontWeight:String,
	?fontStyle:String,
	?textDecoration:String,
	?opacity:String
};
typedef CodeToken = {final from:Int; final to:Int; final kind:CodeTokenKind; @:optional final style:CodeTokenStyle;}
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
