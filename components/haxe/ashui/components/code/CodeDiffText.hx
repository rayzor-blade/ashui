package ashui.components.code;

import ashui.components.code.CodeDocument.CodeLine;
import ashui.components.code.CodeHighlighter.CodeToken;

/**
	The lines of one text of a diff, tokenised only when a row asks for them. A diff of a large file shows a few hundred of its
	lines and folds the rest, so what is kept for the text is its lines (the strings the comparison was made from, not copies of
	them) and a bounded number of tokenised ones: not a line object and a token array for every line, as a `CodeDocument` has.

	Colouring a line needs the lexical state the line before it ended in. A row that follows the one shown before it takes that
	state from it; any other row finds it from a checkpoint kept every `STEP` lines, reached by colouring the lines between and
	forgetting them. `fill` makes the checkpoints a slice at a time, so a jump far into a large file has little left to do.
	A line longer than `CLIP` characters is shown cut there, with an ellipsis, so one very long line cannot cost what the rest
	of the file does.
**/
class CodeDiffText {
	/** Lines between checkpoints of the lexical state. **/
	static inline var STEP = 256;

	/** The most tokenised lines kept; when there are more, they are all let go and the next rows make theirs again. **/
	static inline var KEEP = 1500;

	/** The longest a line is shown. **/
	public static inline var CLIP = CodeDiffer.LONG;

	public var lines(default, null):Array<String> = [""];
	var syntax:CodeHighlighter;
	final kept = new Map<Int, CodeLine>();
	var keptCount = 0;
	/** The lexical state before line `k * STEP`, for each `k` up to `known`. **/
	final checkpoints:Array<String> = [""];
	var known = 0;

	public function new(syntax:CodeHighlighter)
		this.syntax = syntax;

	/** The number of lines. **/
	public var length(get, never):Int;

	inline function get_length():Int
		return lines.length;

	/** Takes other lines, to be coloured by `syntax`, and lets go of everything made for the last. **/
	public function reset(lines:Array<String>, syntax:CodeHighlighter):Void {
		this.lines = lines.length == 0 ? [""] : lines;
		this.syntax = syntax;
		kept.clear();
		keptCount = 0;
		checkpoints.resize(1);
		known = 0;
	}

	/** The line `index`, from 0, with its tokens; an empty line for an index there is no line at. **/
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

	/** The state before line `index`: from the nearest checkpoint, through the lines between it and `index`. **/
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

	/** Makes the checkpoints for the next `budget` lines; true when there are checkpoints all the way to the end. **/
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
