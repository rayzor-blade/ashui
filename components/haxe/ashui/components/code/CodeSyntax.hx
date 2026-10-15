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
		key = switch key { case "js", "jsx": "javascript"; case "ts", "tsx": "typescript"; case "hxx": "haxe"; case "rs": "rust"; case "py": "python"; case "text": "plain"; case _: key; }
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
	inline function markup():Bool return language == "haxe" || language == "javascript" || language == "typescript";

	/** An expression can start markup; a generic such as Map<String, Int> cannot (fb9ee3b). **/
	static function expressionStart(line:String, at:Int):Bool {
		var previous = at - 1;
		while (previous >= 0 && StringTools.isSpace(line, previous)) previous--;
		if (previous < 0 || "=([{,:;>!?&|".indexOf(line.charAt(previous)) >= 0) return true;
		var end = previous + 1;
		while (previous >= 0 && letter(line.charCodeAt(previous))) previous--;
		var word = line.substring(previous + 1, end);
		return word == "return" || word == "yield" || word == "else";
	}
	static function tagAt(line:String, at:Int):Bool {
		var next = line.charAt(at + 1);
		return line.charAt(at) == "<" && (next == ">" || next != "" && letter(line.charCodeAt(at + 1)));
	}

	public function highlight(line:String, state:String):CodeHighlight {
		var tokens:Array<CodeToken> = [];
		if (language == "plain" || language == "text") return {tokens: tokens, state: ""};
		// A compact lexical stack carries nested markup/expressions across lines.
		// Frames contain only grammar states, never source text (fb9ee3b).
		var frames = state == "" ? [] : state.split("|");
		function emit(from:Int, to:Int, kind:CodeTokenKind):Void {
			if (tokens.length > 0 && tokens[tokens.length - 1].kind == kind) {
				var previous = tokens.pop(); tokens.push({from: previous.from, to: to, kind: kind});
			} else tokens.push({from: from, to: to, kind: kind});
		}
		var i = 0, n = line.length;
		while (i < n) {
			var start = i, kind:CodeTokenKind = Plain;
			var frame = frames.length == 0 ? "" : frames[frames.length - 1];
			if (frame == "/*" || frame == "--[[" || frame == "<!--" || frame == "[[") {
				var close = frame == "/*" ? "*/" : frame == "<!--" ? "-->" : "]]";
				var end = line.indexOf(close, i);
				i = end < 0 ? n : end + close.length;
				if (end >= 0) frames.pop();
				kind = frame == "[[" ? StringLiteral : Comment;
			} else if (StringTools.startsWith(frame, "q")) {
				var quote = frame.substr(1);
				while (i < n) {
					if (line.charAt(i) == "\\") i += 2;
					else if (line.substr(i, quote.length) == quote) { i += quote.length; frames.pop(); break; }
					else i++;
				}
				kind = StringLiteral;
			} else if (frame == "text") {
				if (line.substr(i, 4) == "<!--") { frames.push("<!--"); i += 4; kind = Comment; }
				else if (line.substr(i, 2) == "</") { frames.pop(); frames.push("tag-close-name"); i += 2; kind = Operator; }
				else if (tagAt(line, i)) { frames.push("text"); frames.push("tag-open-name"); i++; kind = Operator; }
				else if (line.substr(i, 2) == "$" + "{" || line.charAt(i) == "{") {
					i += line.charAt(i) == "$" ? 2 : 1; frames.push("expr1"); kind = Operator;
				} else {
					i++;
					while (i < n && line.substr(i, 4) != "<!--" && line.substr(i, 2) != "</" && !tagAt(line, i)
						&& line.substr(i, 2) != "$" + "{" && line.charAt(i) != "{") i++;
					kind = MarkupText;
				}
			} else if (StringTools.startsWith(frame, "tag-")) {
				if (line.substr(i, 2) == "/>") { i += 2; frames.pop(); if (frames[frames.length - 1] == "text") frames.pop(); kind = Operator; }
				else if (line.charAt(i) == ">") { i++; frames.pop(); kind = Operator; }
				else if (line.charAt(i) == "{") { i++; frames.push("expr1"); kind = Operator; }
				else if (line.charAt(i) == '"' || line.charAt(i) == "'") { frames.push("q" + line.charAt(i)); i++; kind = StringLiteral; }
				else if (letter(line.charCodeAt(i))) {
					i++;
					while (i < n && (letter(line.charCodeAt(i)) || digit(line.charCodeAt(i)) || "-:.".indexOf(line.charAt(i)) >= 0)) i++;
					kind = StringTools.endsWith(frame, "-name") ? Tag : Attribute;
					if (kind == Tag) frames[frames.length - 1] = frame.substr(0, frame.length - 5);
				} else { i++; kind = StringTools.isSpace(line, start) ? Plain : Operator; }
			} else if ((language != "json" && language != "css" && line.substr(i, 2) == "//")
				|| (language == "python" && line.charAt(i) == "#")
				|| (language == "lua" && line.substr(i, 2) == "--" && line.substr(i, 4) != "--[[")) {
				i = n; kind = Comment;
			} else if ((language != "python" && language != "lua" && line.substr(i, 2) == "/*") || (language == "lua" && line.substr(i, 4) == "--[[")) {
				frames.push(language == "lua" ? "--[[" : "/*");
				i += language == "lua" ? 4 : 2;
				kind = Comment;
			} else if (language == "lua" && line.substr(i, 2) == "[[") {
				frames.push("[["); i += 2; kind = StringLiteral;
			} else if (markup() && tagAt(line, i) && expressionStart(line, i)) {
				frames.push("text"); frames.push("tag-open-name"); i++; kind = Operator;
			} else if (line.charAt(i) == '"' || line.charAt(i) == "'" || line.charAt(i) == "`") {
				var quote = line.charAt(i);
				if (language == "python" && line.substr(i, 3) == quote + quote + quote) quote += quote + quote;
				i += quote.length;
				var closed = false;
				while (i < n) {
					if (line.charAt(i) == "\\") i += 2;
					else if (line.substr(i, quote.length) == quote) { i += quote.length; closed = true; break; }
					else i++;
				}
				if (!closed && (quote.length > 1 || quote == "`" || language == "haxe" || language == "rust" || line.charAt(n - 1) == "\\")) frames.push("q" + quote);
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
				if (StringTools.startsWith(frame, "expr")) {
					var depth = Std.parseInt(frame.substr(4));
					if (line.charAt(start) == "{") frames[frames.length - 1] = "expr" + (depth + 1);
					else if (line.charAt(start) == "}") {
						if (depth == 1) frames.pop(); else frames[frames.length - 1] = "expr" + (depth - 1);
					}
				}
			}
			i = Std.int(Math.min(i, n));
			emit(start, i, kind);
		}
		return {tokens: tokens, state: frames.join("|")};
	}
}
