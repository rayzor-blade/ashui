package ashui.components.code;

import ashui.components.code.CodeHighlighter;

/**
	A source line with compact syntax tokens.
	Stores start, end, and kind as three integers per token. Use `tokenCount`,
	`tokenFrom`, `tokenTo`, and `tokenKind` to avoid allocation. Reading
	`tokens` creates a new array of token objects for external consumers.
**/
class CodeLine {
	/** Token kinds referenced by packed indices. **/
	static final KINDS:Array<CodeTokenKind> = [Plain, Keyword, StringLiteral, Comment, Number, Type, Function, Operator, Tag, Attribute, MarkupText];

	static function indexOfKind(kind:CodeTokenKind):Int
		return switch kind {
			case Plain: 0;
			case Keyword: 1;
			case StringLiteral: 2;
			case Comment: 3;
			case Number: 4;
			case Type: 5;
			case Function: 6;
			case Operator: 7;
			case Tag: 8;
			case Attribute: 9;
			case MarkupText: 10;
		};

	public final text:String;
	public var start = 0;
	var packed:Null<Array<Int>> = null;
	var styles:Null<Array<Null<CodeTokenStyle>>>;

	/** Changes whenever tokens are replaced, allowing cached consumers to detect updates. **/
	public var tokenRevision(default, null) = 0;

	public var incoming:Null<String>;
	public var outgoing = "";
	public var foldEnd = -1;
	public var folded = false;
	public var generation = 0;

	public function new(text:String) this.text = text;

	public var tokenCount(get, never):Int;

	inline function get_tokenCount():Int
		return packed == null ? 0 : Std.int(packed.length / 3);

	public inline function tokenFrom(i:Int):Int
		return packed[i * 3];

	public inline function tokenTo(i:Int):Int
		return packed[i * 3 + 1];

	public inline function tokenKind(i:Int):CodeTokenKind
		return KINDS[packed[i * 3 + 2]];

	public inline function tokenStyle(i:Int):Null<CodeTokenStyle>
		return styles == null ? null : styles[i];

	/** Tokens as objects. Each read allocates an array; assignments repack the tokens. **/
	public var tokens(get, set):Array<CodeToken>;

	function get_tokens():Array<CodeToken>
		return [for (i in 0...tokenCount) {from: tokenFrom(i), to: tokenTo(i), kind: tokenKind(i), style: tokenStyle(i)}];

	function set_tokens(list:Array<CodeToken>):Array<CodeToken> {
		tokenRevision++;
		styles = null;
		if (list.length == 0) {
			packed = null;
			return list;
		}
		var made = new Array<Int>();
		made.resize(list.length * 3);
		for (i in 0...list.length) {
			var token = list[i];
			made[i * 3] = token.from;
			made[i * 3 + 1] = token.to;
			made[i * 3 + 2] = indexOfKind(token.kind);
			if (token.style != null) {
				if (styles == null) { styles = []; styles.resize(list.length); }
				styles[i] = token.style;
			}
		}
		packed = made;
		return list;
	}
}

/** Line cache and display-row mapping shared by code views and editors (e53597f). **/
class CodeDocument {
	public var text(default, null) = "";
	public var lines(default, null):Array<CodeLine> = [];
	public var visible(default, null):Array<Int> = [];
	public var rows(default, null):Array<Int> = [];
	/** Number of lines re-lexed by the last update, useful in performance diagnostics. **/
	public var highlighted(default, null) = 0;
	public var generation(default, null) = 0;
	/** Matching bracket offsets, populated during fold detection (357ddef). **/
	public final brackets = new Map<Int, Int>();
	var syntax:CodeHighlighter;

	public function new(text:String, syntax:CodeHighlighter) update(text, syntax);

	public function update(text:String, syntax:CodeHighlighter):Bool {
		if (this.text == text && this.syntax == syntax && lines.length > 0) return false;
		var sameSyntax = this.syntax == syntax;
		this.syntax = syntax;
		this.text = text;
		generation++;
		var raw = text.split("\n"), old = lines, prefix = 0, suffix = 0;
		if (sameSyntax) {
			while (prefix < old.length && prefix < raw.length && old[prefix].text == raw[prefix]) prefix++;
			while (suffix < old.length - prefix && suffix < raw.length - prefix && old[old.length - 1 - suffix].text == raw[raw.length - 1 - suffix]) suffix++;
		}
		lines = [];
		var start = 0, state = "";
		highlighted = 0;
		for (i in 0...raw.length) {
			var line = i < prefix ? old[i] : i >= raw.length - suffix ? old[old.length - raw.length + i] : new CodeLine(raw[i]);
			line.start = start;
			line.generation = generation;
			line.foldEnd = -1;
			if (line.incoming != state) {
				var result = syntax.highlight(line.text, state);
				line.tokens = result.tokens;
				line.incoming = state;
				line.outgoing = result.state;
				highlighted++;
			}
			state = line.outgoing;
			lines.push(line);
			start += line.text.length + 1;
		}
		// Brackets in comments and strings never become folds. Keep nested regions,
		// including when an outer fold is closed, so opening it restores its children.
		brackets.clear();
		var stack:Array<{line:Int, char:Int, index:Int}> = [];
		for (i in 0...lines.length) {
			var line = lines[i], tokenIndex = 0, tokenCount = line.tokenCount, content = line.text;
			for (column in 0...content.length) {
				var c = StringTools.fastCodeAt(content, column);
				// Only a bracket is looked at: the tokens are walked to it, and it is skipped inside a comment or a string.
				var opens = c == "{".code || c == "[".code || c == "(".code, closes = c == "}".code || c == "]".code || c == ")".code;
				if (!opens && !closes) continue;
				while (tokenIndex < tokenCount && line.tokenTo(tokenIndex) <= column) tokenIndex++;
				if (tokenIndex < tokenCount && line.tokenFrom(tokenIndex) <= column
					&& (line.tokenKind(tokenIndex) == Comment || line.tokenKind(tokenIndex) == StringLiteral || line.tokenKind(tokenIndex) == MarkupText)) continue;
				if (opens) stack.push({line: i, char: c, index: line.start + column});
				else if (stack.length > 0) {
					var open = stack[stack.length - 1];
					if (open.char == (c == "}".code ? "{".code : c == "]".code ? "[".code : "(".code)) {
						stack.pop();
						brackets.set(open.index, line.start + column);
						brackets.set(line.start + column, open.index);
						if (open.line < i && open.char != "(".code) lines[open.line].foldEnd = i;
					}
				}
			}
		}
		for (line in lines) if (line.foldEnd < 0) line.folded = false;
		mapRows();
		return true;
	}

	/** Returns the bracket pair adjacent to the caret, opening offset first. Ignores brackets in strings and comments. **/
	public function matchingBrackets(caret:Int):Array<Int> {
		var at = brackets.exists(caret - 1) ? caret - 1 : caret;
		var other = brackets.get(at);
		return other == null ? [] : [Std.int(Math.min(at, other)), Std.int(Math.max(at, other))];
	}

	public function mapRows():Void {
		visible = []; rows = [];
		var hiddenTo = -1, row = -1;
		for (i in 0...lines.length) {
			if (i > hiddenTo) {
				row++;
				visible.push(i);
				if (lines[i].folded) hiddenTo = lines[i].foldEnd;
			}
			rows.push(row);
		}
	}

	/** Toggles folding at a zero-based source line. Returns false if the line has no foldable block. **/
	public function toggleFold(line:Int):Bool {
		if (line < 0 || line >= lines.length || lines[line].foldEnd < 0) return false;
		lines[line].folded = !lines[line].folded;
		mapRows();
		return true;
	}

	/** Expands folds hiding a source offset before programmatic selection or navigation. **/
	public function unfoldAt(index:Int):Bool {
		var at = lineAt(index), changed = false;
		for (i in 0...at) if (lines[i].folded && lines[i].foldEnd >= at) { lines[i].folded = false; changed = true; }
		if (changed) mapRows();
		return changed;
	}

	public function lineAt(index:Int):Int {
		var low = 0, high = lines.length - 1;
		while (low < high) {
			var middle = (low + high + 1) >> 1;
			if (lines[middle].start <= index) low = middle; else high = middle - 1;
		}
		return low;
	}
}
