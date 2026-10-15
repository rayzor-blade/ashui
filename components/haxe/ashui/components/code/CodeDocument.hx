package ashui.components.code;

import ashui.components.code.CodeHighlighter;

class CodeLine {
	public final text:String;
	public var start = 0;
	public var tokens:Array<CodeToken> = [];
	public var incoming:Null<String>;
	public var outgoing = "";
	public var foldEnd = -1;
	public var folded = false;
	public var generation = 0;
	public function new(text:String) this.text = text;
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
	/** Matching source offsets, filled alongside fold detection (357ddef). **/
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
		var stack:Array<{line:Int, char:String, index:Int}> = [];
		for (i in 0...lines.length) {
			var line = lines[i], tokenIndex = 0;
			for (column in 0...line.text.length) {
				while (tokenIndex < line.tokens.length && line.tokens[tokenIndex].to <= column) tokenIndex++;
				if (tokenIndex < line.tokens.length && line.tokens[tokenIndex].from <= column
					&& (line.tokens[tokenIndex].kind == Comment || line.tokens[tokenIndex].kind == StringLiteral || line.tokens[tokenIndex].kind == MarkupText)) continue;
				var c = line.text.charAt(column);
				if (c == "{" || c == "[" || c == "(") stack.push({line: i, char: c, index: line.start + column});
				else if ((c == "}" || c == "]" || c == ")") && stack.length > 0) {
					var open = stack[stack.length - 1];
					if (open.char == (c == "}" ? "{" : c == "]" ? "[" : "(")) {
						stack.pop();
						brackets.set(open.index, line.start + column);
						brackets.set(line.start + column, open.index);
						if (open.line < i && open.char != "(") lines[open.line].foldEnd = i;
					}
				}
			}
		}
		for (line in lines) if (line.foldEnd < 0) line.folded = false;
		mapRows();
		return true;
	}

	/** Pair adjacent to a caret, with the opening offset first; strings/comments have none. **/
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

	/** Toggle a zero-based source line; return false when it has no block. **/
	public function toggleFold(line:Int):Bool {
		if (line < 0 || line >= lines.length || lines[line].foldEnd < 0) return false;
		lines[line].folded = !lines[line].folded;
		mapRows();
		return true;
	}

	/** Reveal a source position before programmatic selection or navigation. **/
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
