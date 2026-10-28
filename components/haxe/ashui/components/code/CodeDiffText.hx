package ashui.components.code;

import ashui.components.code.CodeDocument.CodeLine;
import ashui.components.code.CodeHighlighter.CodeToken;

/**
	Source lines with on-demand syntax tokens and a bounded token cache.
	Keeps the comparison strings rather than copying them or creating a
	`CodeLine` for every source line.

	Lexical checkpoints every `STEP` lines preserve multiline syntax state.
	`fill` builds checkpoints in batches to reduce work on distant jumps.
	Lines longer than `CLIP` display an ellipsis at the limit.
**/
class CodeDiffText {
	/** Number of lines between lexical checkpoints. **/
	static inline var STEP = 256;

	/** Maximum cached tokenized lines before clearing the cache. **/
	static inline var KEEP = 1500;

	/** Maximum displayed characters per line. **/
	public static inline var CLIP = CodeDiffer.LONG;

	public var lines(default, null):Array<String> = [""];
	var syntax:CodeHighlighter;
	final kept = new Map<Int, CodeLine>();
	var keptCount = 0;
	/** Lexical state before line `k * STEP`, for checkpoints through `known`. **/
	final checkpoints:Array<String> = [""];
	var known = 0;

	public function new(syntax:CodeHighlighter)
		this.syntax = syntax;

	/** Source line count. **/
	public var length(get, never):Int;

	inline function get_length():Int
		return lines.length;

	/** Replaces source lines and highlighter, releasing the previous caches. **/
	public function reset(lines:Array<String>, syntax:CodeHighlighter):Void {
		this.lines = lines.length == 0 ? [""] : lines;
		this.syntax = syntax;
		kept.clear();
		keptCount = 0;
		checkpoints.resize(1);
		known = 0;
	}

	/** Returns a tokenized line by zero-based index, or an empty line for an invalid index. **/
	public function line(index:Int):CodeLine {
		var found = kept.get(index);
		if (found != null)
			return found;
		if (index < 0 || index >= lines.length)
			return new CodeLine("");
		var before = kept.get(index - 1);
		var state = before != null ? before.outgoing : stateAt(index);
		if (keptCount >= KEEP) {
			kept.clear();
			keptCount = 0;
		}
		var text = lines[index], cut = text.length > CLIP;
		var shown = cut ? text.substr(0, CLIP) : text;
		var result = syntax.highlight(shown, state);
		var line = new CodeLine(cut ? shown + "…" : shown);
		if (cut) {
			var tokens = result.tokens.copy();
			tokens.push({from: CLIP, to: CLIP + 1, kind: Plain});
			line.tokens = tokens;
		} else
			line.tokens = result.tokens;
		line.incoming = state;
		line.outgoing = result.state;
		kept.set(index, line);
		keptCount++;
		return line;
	}

	/** Resolves lexical state before a line from the nearest checkpoint. **/
	function stateAt(index:Int):String {
		var c = Std.int(index / STEP);
		if (c > known)
			c = known;
		var state = checkpoints[c], at = c * STEP;
		while (at < index) {
			state = syntax.highlight(clip(lines[at]), state).state;
			at++;
			if (at % STEP == 0 && at / STEP > known)
				note(at, state);
		}
		return state;
	}

	function note(at:Int, state:String):Void {
		known = Std.int(at / STEP);
		checkpoints[known] = state;
	}

	static inline function clip(text:String):String
		return text.length > CLIP ? text.substr(0, CLIP) : text;

	/** Builds checkpoints for up to `budget` more lines. Returns true when the entire text is covered. **/
	public function fill(budget:Int):Bool {
		var at = known * STEP, end = lines.length;
		if (at >= end)
			return true;
		var state = checkpoints[known], stop = at + budget < end ? at + budget : end;
		while (at < stop) {
			state = syntax.highlight(clip(lines[at]), state).state;
			at++;
			if (at % STEP == 0)
				note(at, state);
		}
		return at >= end;
	}
}
