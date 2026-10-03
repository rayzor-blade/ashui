package ashui.ui;

import ashui.core.externs.TextNative;
import ashui.input.Clipboard;
import ashui.input.Events;
import ashui.input.Interaction;
import ashui.reactive.Computed;
import ashui.reactive.Signal;

/** Where a caret can stand: a string index, its x from the text's left, and its line. **/
typedef CaretStop = {index:Int, x:Float, line:Int};

/**
	The editing behind `TextField` and `TextArea`: a value, a caret and a
	selection over it, the keys and pointer moves that change them, and the
	caret's blink. The views draw what it holds and hand it their events.

	Positions are indices in the Haxe string. The caret stands only on the
	character boundaries the text engine reports for the view's font, laid
	out on one line, or wrapped at `wrapWidth` when it is above 0.
**/
class TextEditing {
	/** Seconds the caret shows, then hides, while the view has focus. **/
	static inline var BLINK = 0.53;
	/** Seconds each blink fades over, eased, as macOS softens its caret. **/
	static inline var FADE = 0.06;

	/** The text being edited, which edits set. **/
	public final value:Signal<String>;
	/** Where the caret is, and where the selection started; equal when nothing is selected. **/
	public final caret = Signal.make(0);
	public final anchor = Signal.make(0);
	/** Whether the view has focus. **/
	public final focused = Signal.make(false);
	/** The caret's opacity: 1 shown, 0 hidden, between while it fades. **/
	public final caretAlpha = Signal.make(1.0);
	/** An input method's text being composed at the caret, not yet in the value; empty when none. **/
	public final composing = Signal.make("");
	/** Where the input method's caret is in `composing`, or -1 for its end. **/
	var composeCursor = -1;
	/** What a press selects as it is dragged: 1 characters, 2 words, 3 paragraphs; and what the press first selected. **/
	var granularity = 1;
	var pressRange = {from: 0, to: 0};
	/** The theme's small text size, which the view's text is set in and measured at. **/
	public final fontSize:Computed<Single>;
	/** Whether Enter starts a new line and Up and Down move between lines, as in a text area. **/
	public final multiline:Bool;
	/** The width lines wrap at; 0 keeps the text on one line. **/
	public final wrapWidth:Float;

	/** Called with the new value after each edit. **/
	public var onInput:Null<String->Void>;
	/** Called with the value on Enter, or Command+Enter when multiline. **/
	public var onSubmit:Null<String->Void>;
	/** Takes focus away, as Escape does. **/
	public var onEscape:Null<Void->Void>;
	/** Lines a page moves by, for Page Up and Page Down. **/
	public var pageLines:Void->Int = () -> 10;

	/** The text node the stops are measured for; set by the view. **/
	public var text:Null<Text>;
	/** The view's input state, whose `disabled` stops editing; set by the view. **/
	public var interaction:Null<Interaction>;

	var stops:Array<CaretStop> = [{index: 0, x: 0, line: 0}];
	var measured:Null<String> = null;
	var measuredSize = 0.0;
	/** The height of a line, and how many the value takes, as last measured. **/
	public var lineHeight(default, null) = 0.0;
	public var lines(default, null) = 1;
	/** The x the caret keeps to across Up and Down, until it moves another way. **/
	var goalX:Null<Float> = null;
	var dragging = false;
	var caretOn = true;
	var fadeId = 0;
	var blinkTimer:Null<ashui.animation.AnimationScheduler.Timer> = null;

	public function new(value:Signal<String>, multiline:Bool, wrapWidth:Float) {
		this.value = value;
		this.multiline = multiline;
		this.wrapWidth = wrapWidth;
		fontSize = ashui.theme.Themed.fontSize(TextSm);
	}

	// --- geometry ---

	/** The caret stops of `s`, from the text engine, measured once per value and font size. **/
	public function stopsFor(s:String):Array<CaretStop> {
		var size:Float = fontSize.get();
		if ((measured == s && measuredSize == size) || text == null)
			return stops;
		var capacity = s.length + 2;
		var out = new hl.Bytes(capacity * 12);
		var info = new hl.Bytes(8);
		var n = TextNative.blinc_text_carets(text.tree.ptr, text.node.id, ashui.core.Utf8.encode(s), size, wrapWidth, out, capacity, info);
		if (n > 0 && n <= capacity) {
			stops = [for (i in 0...n) {index: Std.int(out.getF32(i * 12)), x: out.getF32(i * 12 + 4), line: Std.int(out.getF32(i * 12 + 8))}];
			lineHeight = info.getF32(0);
			lines = Std.int(info.getF32(4));
			measured = s;
			measuredSize = size;
		}
		return stops;
	}

	/** The stop the caret before string index `i` stands at. **/
	public function stopAt(i:Int, s:String):CaretStop {
		var list = stopsFor(s);
		var best = list[0];
		for (stop in list)
			if (stop.index <= i)
				best = stop;
		return best;
	}

	/** The stop nearest `x` on `line`, or on the nearest line there is. **/
	public function indexAt(x:Float, line:Int):Int {
		var list = stopsFor(value.get());
		var last = list[list.length - 1].line;
		var on = Std.int(Math.max(0, Math.min(last, line)));
		var best = list[0].index;
		var distance = Math.POSITIVE_INFINITY;
		for (stop in list) {
			if (stop.line != on)
				continue;
			var d = Math.abs(stop.x - x);
			if (d < distance) {
				distance = d;
				best = stop.index;
			}
		}
		return best;
	}

	/** The line a point `y` from the text's top falls on. **/
	public function lineAtY(y:Float):Int
		return lineHeight > 0 ? Std.int(Math.floor(y / lineHeight)) : 0;

	/** The width of `line`: its last stop's x. **/
	public function lineWidth(line:Int):Float {
		var w = 0.0;
		for (stop in stopsFor(value.get()))
			if (stop.line == line)
				w = Math.max(w, stop.x);
		return w;
	}

	/** The stop after, or before, string index `i`. **/
	function step(i:Int, forward:Bool):Int {
		var list = stopsFor(value.get());
		if (forward) {
			for (stop in list)
				if (stop.index > i)
					return stop.index;
			return list[list.length - 1].index;
		}
		var previous = 0;
		for (stop in list) {
			if (stop.index >= i)
				return previous;
			previous = stop.index;
		}
		return previous;
	}

	/** Where the word before, or after, `i` starts or ends. **/
	function word(i:Int, forward:Bool):Int {
		var s = value.get();
		inline function space(at:Int)
			return StringTools.isSpace(s, at);
		if (forward) {
			var j = i;
			while (j < s.length && space(j))
				j++;
			while (j < s.length && !space(j))
				j++;
			return j;
		}
		var j = i;
		while (j > 0 && space(j - 1))
			j--;
		while (j > 0 && !space(j - 1))
			j--;
		return j;
	}

	/** The first, or last, stop on the line `i` is on. **/
	function lineEdge(i:Int, end:Bool):Int {
		var line = stopAt(i, value.get()).line;
		var edge = i;
		var found = false;
		for (stop in stopsFor(value.get()))
			if (stop.line == line) {
				if (!end && !found) {
					edge = stop.index;
					found = true;
				}
				if (end)
					edge = stop.index;
			}
		return edge;
	}

	/** The stop `by` lines down (up when negative) from `i`, keeping to the goal x. **/
	function vertical(i:Int, by:Int):Int {
		var here = stopAt(i, value.get());
		if (goalX == null)
			goalX = here.x;
		var line = here.line + by;
		var list = stopsFor(value.get());
		if (line < 0)
			return 0;
		if (line > list[list.length - 1].line)
			return value.get().length;
		return indexAt(goalX, line);
	}

	// --- editing ---

	function move(to:Int, select:Bool, ?keepGoal = false):Void {
		if (!keepGoal)
			goalX = null;
		caret.set(to);
		if (!select)
			anchor.set(to);
		restartBlink();
	}

	/** The selection as string indices, `from` before `to`. **/
	public function selectionRange():{from:Int, to:Int} {
		return {from: Std.int(Math.min(caret.get(), anchor.get())), to: Std.int(Math.max(caret.get(), anchor.get()))};
	}

	/** The selected text. **/
	public function selection():String {
		var r = selectionRange();
		return value.get().substring(r.from, r.to);
	}

	/** The text as shown: the value, with any composition in place of the selection. **/
	public function display():String {
		var c = composing.get();
		if (c == "")
			return value.get();
		var r = selectionRange();
		var s = value.get();
		return s.substr(0, r.from) + c + s.substr(r.to);
	}

	/** Where the caret is shown in `display()`: in the composition while there is one. **/
	public function displayCaret():Int {
		var c = composing.get();
		if (c == "")
			return caret.get();
		return selectionRange().from + (composeCursor >= 0 ? composeCursor : c.length);
	}

	/** The composition's range in `display()`, or null while there is none. **/
	public function composedRange():Null<{from:Int, to:Int}> {
		var c = composing.get();
		if (c == "")
			return null;
		var from = selectionRange().from;
		return {from: from, to: from + c.length};
	}

	/** An input method's composition changed; empty text when it ends, as it commits or cancels. **/
	public function compose(e:CompositionEvent):Void {
		if (disabled())
			return;
		composeCursor = e.cursor;
		composing.set(e.text);
		restartBlink();
	}

	/** Replaces the selection with `insert`, leaving the caret after it. **/
	public function replace(insert:String):Void {
		var s = value.get();
		var r = selectionRange();
		var next = s.substr(0, r.from) + insert + s.substr(r.to);
		value.set(next);
		move(r.from + insert.length, false);
		if (onInput != null)
			onInput(next);
	}

	/** Deletes the selection, or from the caret to `to` when nothing is selected. **/
	function erase(to:Int):Void {
		if (caret.get() == anchor.get())
			anchor.set(to);
		replace("");
	}

	function disabled():Bool
		return interaction != null && interaction.disabled.get();

	/** Inserts typed text in place of the selection; a line break is a space unless multiline. **/
	public function type(e:TextInputEvent):Void {
		if (!disabled())
			replace(multiline ? e.text : ~/\r\n|\r|\n/g.replace(e.text, " "));
	}

	/** Moves, selects, deletes, copies, pastes or submits for a key going down. **/
	public function key(e:KeyEvent):Void {
		// The input method handles keys while it composes.
		if (disabled() || composing.get() != "")
			return;
		var mac = Sys.systemName() == "Mac";
		var byLine = e.superKey || (e.control && !mac);
		var at = caret.get();
		var selected = caret.get() != anchor.get();
		var length = value.get().length;
		switch e.key {
			case Named(ArrowLeft):
				move(byLine ? lineEdge(at, false) : e.alt ? word(at, false) : selected && !e.shift ? selectionRange().from : step(at, false), e.shift);
			case Named(ArrowRight):
				move(byLine ? lineEdge(at, true) : e.alt ? word(at, true) : selected && !e.shift ? selectionRange().to : step(at, true), e.shift);
			case Named(ArrowUp):
				if (multiline && !byLine)
					move(vertical(at, -1), e.shift, true);
				else
					move(0, e.shift);
			case Named(ArrowDown):
				if (multiline && !byLine)
					move(vertical(at, 1), e.shift, true);
				else
					move(length, e.shift);
			case Named(PageUp):
				move(multiline ? vertical(at, -pageLines()) : 0, e.shift, true);
			case Named(PageDown):
				move(multiline ? vertical(at, pageLines()) : length, e.shift, true);
			case Named(Home):
				move(multiline && !byLine ? lineEdge(at, false) : 0, e.shift);
			case Named(End):
				move(multiline && !byLine ? lineEdge(at, true) : length, e.shift);
			case Named(Backspace):
				erase(byLine ? lineEdge(at, false) : e.alt ? word(at, false) : step(at, false));
			case Named(Delete):
				erase(byLine ? lineEdge(at, true) : e.alt ? word(at, true) : step(at, true));
			case Named(Escape):
				if (onEscape != null)
					onEscape();
			case Named(Enter):
				// Enter is a new line in a text area; with Command, or in a field, it submits.
				e.preventDefault();
				if (multiline && !byLine)
					replace("\n");
				else if (onSubmit != null)
					onSubmit(value.get());
			case Named(Tab):
				return;
			case Named(Space):
				// Typed as text; it must not click the view as well.
				e.preventDefault();
			case Character(c) if ((c == "a" || c == "A") && (e.superKey || e.control)):
				anchor.set(0);
				move(length, true);
			case Character(c) if ((c == "c" || c == "C") && (e.superKey || e.control)):
				if (selected)
					Clipboard.setText(selection());
			case Character(c) if ((c == "x" || c == "X") && (e.superKey || e.control)):
				if (selected) {
					Clipboard.setText(selection());
					replace("");
				}
			case Character(c) if ((c == "v" || c == "V") && (e.superKey || e.control)):
				var pasted = Clipboard.text();
				// A single line takes a pasted line break as a space.
				if (!multiline)
					pasted = ~/\r\n|\r|\n/g.replace(pasted, " ");
				else
					pasted = ~/\r\n|\r/g.replace(pasted, "\n");
				if (pasted != "" || selected)
					replace(pasted);
			case _:
				return;
		}
	}

	/** Keeps Space and Enter coming up from clicking the view. **/
	public function keyUp(e:KeyEvent):Void {
		if (e.key.match(Named(Space) | Named(Enter)))
			e.preventDefault();
	}

	/**
		A press at `(x, y)` from the text's top-left: the caret goes there, and
		Shift extends the selection to it. A double-click selects the word
		there and a triple-click its paragraph; dragging after either extends
		the selection by words or paragraphs.
	**/
	public function press(x:Float, y:Float, shift:Bool, clicks = 1):Void {
		if (disabled())
			return;
		var at = indexAt(x, lineAtY(y));
		granularity = clicks >= 3 ? 3 : clicks;
		if (granularity == 1 || shift) {
			move(at, shift);
		} else {
			pressRange = unit(at);
			anchor.set(pressRange.from);
			move(pressRange.to, true);
		}
		dragging = true;
	}

	/** The pointer moved to `(x, y)` from the text's top-left: a drag selects to it, by the unit the press chose. **/
	public function drag(x:Float, y:Float):Void {
		if (!dragging || interaction == null || !interaction.pressed.get())
			return;
		var at = indexAt(x, lineAtY(y));
		if (granularity == 1) {
			move(at, true);
			return;
		}
		// The selection keeps the unit first pressed and reaches the unit under the pointer.
		var here = unit(at);
		if (here.from < pressRange.from) {
			anchor.set(pressRange.to);
			move(here.from, true);
		} else {
			anchor.set(pressRange.from);
			move(Std.int(Math.max(here.to, pressRange.to)), true);
		}
	}

	/** The word, or paragraph, around string index `i`, as the press's granularity takes it. **/
	function unit(i:Int):{from:Int, to:Int} {
		var s = value.get();
		if (granularity >= 3) {
			var from = s.lastIndexOf("\n", i - 1) + 1;
			var to = s.indexOf("\n", i);
			return {from: i > 0 ? from : 0, to: to < 0 ? s.length : to};
		}
		inline function isWord(at:Int)
			return at >= 0 && at < s.length && !StringTools.isSpace(s, at) && "\n.,;:!?()[]{}\"'".indexOf(s.charAt(at)) < 0;
		var from = i, to = i;
		while (from > 0 && isWord(from - 1))
			from--;
		while (to < s.length && isWord(to))
			to++;
		// Between words, the run of spaces or punctuation there.
		if (from == to && to < s.length)
			to++;
		return {from: from, to: to};
	}

	/** The press ended: dragging selects no further. **/
	public function release():Void {
		dragging = false;
	}

	/** The view gained focus. **/
	public function focus():Void {
		focused.set(true);
		restartBlink();
	}

	/** The view lost focus: any composition is dropped and the selection collapses to the caret. **/
	public function blur():Void {
		focused.set(false);
		dragging = false;
		composing.set("");
		anchor.set(caret.get());
	}

	// --- caret blink ---

	/** Whether the caret is drawn at all: the view has focus in the active, visible window. **/
	public function showsCaret():Bool
		return focused.get() && ashui.input.WindowState.active.get() && ashui.input.WindowState.visible.get();

	/** Shows the caret steadily, without blinking. **/
	public function stopBlink():Void {
		if (blinkTimer != null)
			blinkTimer.cancel();
		blinkTimer = null;
		fadeId++;
		caretOn = true;
		caretAlpha.set(1);
	}

	/** Shows the caret at once and starts its blink afresh. **/
	public function restartBlink():Void {
		if (blinkTimer != null)
			blinkTimer.cancel();
		// Typing or moving shows the caret at once, with no fade.
		fadeId++;
		caretOn = true;
		caretAlpha.set(1);
		blinkTimer = ashui.animation.AnimationScheduler.main.after(BLINK, blink);
	}

	/** Starts the caret fading out or in, and sets the next blink while the view has focus. **/
	function blink():Void {
		blinkTimer = null;
		if (!showsCaret()) {
			stopBlink();
			return;
		}
		caretOn = !caretOn;
		fadeTo(caretOn ? 1 : 0);
		blinkTimer = ashui.animation.AnimationScheduler.main.after(BLINK, blink);
	}

	/** Eases the caret's opacity to `target` over `FADE`; frames are drawn only while it moves. **/
	function fadeTo(target:Float):Void {
		var id = ++fadeId;
		var from = caretAlpha.get();
		var t = 0.0;
		ashui.animation.AnimationScheduler.main.addTicker(dt -> {
			if (id != fadeId)
				return false;
			t = Math.min(1, t + dt / FADE);
			// Ease in and out: slow at both ends.
			var eased = t * t * (3 - 2 * t);
			caretAlpha.set(from + (target - from) * eased);
			return t < 1;
		});
	}

	/** Whether a blink is waiting to fire; for tests. **/
	@:noCompletion public function blinking():Bool
		return blinkTimer != null;
}
