package ashui.components.code;

import ashui.components.code.CodeHighlighter;

/**
	Small lexical highlighters, following Blinc's token/span model (e53597f).
	These color code; they are not parsers or language servers. Applications
	can supply a CodeHighlighter for their own grammar.
**/
class CodeSyntax implements CodeHighlighter {
	static final builtins = new Map<String, CodeSyntax>();
	final words = new Map<String, Bool>();
	final language:String;

	public static function forLanguage(language:String):CodeHighlighter {
		var key = language == null ? "plain" : language.toLowerCase();
		key = switch key { case "js": "javascript"; case "ts": "typescript"; case "rs": "rust"; case "py": "python"; case "text": "plain"; case _: key; }
		if (["haxe", "javascript", "typescript", "rust", "json", "css", "python", "lua", "plain"].indexOf(key) < 0) key = "plain";
		if (!builtins.exists(key)) builtins.set(key, new CodeSyntax(key));
		return builtins.get(key);
	}

	function new(language:String) {
		this.language = language;
		var keywords = switch language {
			case "haxe": "abstract break case cast catch class continue default do dynamic else enum extends extern false final for function if implements import in inline interface macro new null operator overload override package private public return static super switch this throw to true try typedef untyped using var while";
			case "javascript", "typescript": "abstract as async await break case catch class const continue debugger declare default delete do else enum export extends false finally for from function get if implements import in instanceof interface keyof let new null of private protected public readonly return satisfies set static super switch this throw true try type typeof undefined var void while yield";
			case "rust": "as async await break const continue crate dyn else enum extern false fn for if impl in let loop match mod move mut pub ref return self Self static struct super trait true type unsafe use where while";
			case "python": "and as assert async await break class continue def del elif else except False finally for from global if import in is lambda None nonlocal not or pass raise return True try while with yield";
			case "lua": "and break do else elseif end false for function goto if in local nil not or repeat return then true until while";
			case "json": "true false null";
			case _: "";
		}
		for (word in keywords.split(" ")) words.set(word, true);
	}

	static inline function digit(c:Int):Bool return c >= 48 && c <= 57;
	static inline function letter(c:Int):Bool return c >= 65 && c <= 90 || c >= 97 && c <= 122 || c == 95 || c == 36 || c >= 128;

	public function highlight(line:String, state:String):CodeHighlight {
		var tokens:Array<CodeToken> = [];
		if (language == "plain" || language == "text") return {tokens: tokens, state: ""};
		var i = 0, n = line.length;
		while (i < n) {
			var start = i, kind:CodeTokenKind = Plain;
			if (state == "comment" || state == "lua-comment") {
				var close = state == "comment" ? "*/" : "]]";
				var end = line.indexOf(close, i);
				i = end < 0 ? n : end + close.length;
				if (end >= 0) state = "";
				kind = Comment;
			} else if (state != "") {
				var quote = state;
				while (i < n) {
					if (line.charAt(i) == "\\") i += 2;
					else if (line.substr(i, quote.length) == quote) { i += quote.length; state = ""; break; }
					else i++;
				}
				kind = StringLiteral;
			} else if ((language != "json" && language != "css" && line.substr(i, 2) == "//")
				|| (language == "python" && line.charAt(i) == "#")
				|| (language == "lua" && line.substr(i, 2) == "--" && line.substr(i, 4) != "--[[")) {
				i = n; kind = Comment;
			} else if ((language != "python" && language != "lua" && line.substr(i, 2) == "/*") || (language == "lua" && line.substr(i, 4) == "--[[")) {
				state = language == "lua" ? "lua-comment" : "comment";
				var close = language == "lua" ? "]]" : "*/";
				var end = line.indexOf(close, i + (language == "lua" ? 4 : 2));
				i = end < 0 ? n : end + 2;
				if (end >= 0) state = "";
				kind = Comment;
			} else if (line.charAt(i) == '"' || line.charAt(i) == "'" || line.charAt(i) == "`") {
				var quote = line.charAt(i);
				if (language == "python" && line.substr(i, 3) == quote + quote + quote) quote += quote + quote;
				i += quote.length;
				state = quote;
				while (i < n) {
					if (line.charAt(i) == "\\") i += 2;
					else if (line.substr(i, quote.length) == quote) { i += quote.length; state = ""; break; }
					else i++;
				}
				if (quote.length == 1 && quote != "`") state = "";
				kind = StringLiteral;
			} else if (digit(line.charCodeAt(i))) {
				i++;
				while (i < n && "0123456789abcdefABCDEFxXoObB._eE".indexOf(line.charAt(i)) >= 0) i++;
				kind = Number;
			} else if (letter(line.charCodeAt(i))) {
				i++;
				while (i < n && (letter(line.charCodeAt(i)) || digit(line.charCodeAt(i)))) i++;
				var word = line.substring(start, i), next = i;
				while (next < n && StringTools.isSpace(line, next)) next++;
				kind = words.exists(word) ? Keyword : line.charAt(next) == "(" ? Function : word.charCodeAt(0) >= 65 && word.charCodeAt(0) <= 90 ? Type : Plain;
			} else {
				i++;
				kind = "{}[]()+-*/%=!<>?:&|~^;,.".indexOf(line.charAt(start)) >= 0 ? Operator : Plain;
			}
			i = Std.int(Math.min(i, n));
			if (tokens.length > 0 && tokens[tokens.length - 1].kind == kind) {
				var previous = tokens.pop();
				tokens.push({from: previous.from, to: i, kind: kind});
			} else tokens.push({from: start, to: i, kind: kind});
		}
		return {tokens: tokens, state: state};
	}
}
