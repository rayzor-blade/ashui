package ashui.ui;

import ashui.core.externs.TextNative;
import ashui.input.Clipboard;
import ashui.input.Events;
import ashui.input.Interaction;
import ashui.reactive.Computed;
import ashui.reactive.Signal;

/** A valid caret position: string index, horizontal text offset, and line index. **/
typedef CaretStop = {index:Int, x:Float, line:Int};

/**
	Shared editing state and behavior for `TextField` and `TextArea`.
	Owns the text value, caret, selection, input handling, and caret blink.
	Views render this state and forward their events.

	Positions use Haxe string indices. Caret movement follows character
	boundaries from the text engine. Text stays on one line unless
	`wrapWidth` is greater than zero.
**/
class TextEditing {
	/** Time the caret remains visible or hidden during blinking, in seconds. **/
	static inline var BLINK = 0.53;

	/** Caret fade duration in seconds. **/
	static inline var FADE = 0.06;

	/** Editable text signal, updated by edits. **/
	public final value:Signal<String>;

	/** Caret offset. `anchor` marks the selection start; equal offsets mean no selection. **/
	public final caret = Signal.make(0);

	public final anchor = Signal.make(0);

	/** Whether the text view has focus. **/
	public final focused = Signal.make(false);

	/** Caret opacity: zero when hidden, one when visible, with intermediate values during fades. **/
	public final caretAlpha = Signal.make(1.0);

	/** Uncommitted IME text at the caret. Empty when no composition is active. **/
	public final composing = Signal.make("");

	/** Caret offset within the composition, or -1 for the composition end. **/
	var composeCursor = -1;

	/** Drag selection unit: 1 for characters, 2 for words, or 3 for paragraphs. **/
	var granularity = 1;

	var pressRange = {from: 0, to: 0};

	/** Resolved CSS font size. Uses the theme small-text size before styling (e8a1b50). **/
	public final fontSize:Computed<Single>;

	/** Enables newlines and vertical caret movement for multiline editing. **/
	public final multiline:Bool;

	/** Wrapping width. Zero keeps text on one line. **/
	public var wrapWidth(default, set):Float;

	final styledSize = Signal.make((null : Null<Single>));
	final geometry = Signal.make(0);

	static final byText = new haxe.ds.ObjectMap<ashui.css.Identity, TextEditing>();
	static var styledHook = false;
	static final FONT_FIELDS = ["font-family", "font-weight", "font-style", "line-height", "letter-spacing"];

	var fontFields:Array<Null<String>> = [];

	/** Receives the new value after each edit. **/
	public var onInput:Null<String->Void>;

	/** Runs immediately before a text replacement, allowing the editor to capture undo state (e53597f). **/
	public var onBeforeInput:Null<Void->Void>;

	/** Disables edits while preserving selection and copying. **/
	public var readOnly = false;

	/** Optional geometry for virtualized text. Ordinary fields use native text shaping. **/
	public var metrics:Null<TextGeometry>;

	/** Receives the value on Enter, or the platform submit shortcut for multiline text. **/
	public var onSubmit:Null<String->Void>;

	/** Handles Escape, typically by clearing focus. **/
	public var onEscape:Null<Void->Void>;

	/** Returns the number of lines moved by Page Up and Page Down. **/
	public var pageLines:Void->Int = () -> 10;

	/** Text node used for measuring caret stops. Supplied by the view. **/
	public var text:Null<Text>;

	/**
		Password mask character used for display and measurement. Null displays
		the value normally. A mask also disables copying and cutting.
	**/
	public var mask:Null<String> = null;

	/** Reveals masked text while true. Copying remains disabled. **/
	public final revealed = ashui.reactive.Signal.make(false);

	/** Filters typed or pasted text before insertion. Null accepts all text. **/
	public var accept:Null<String->String> = null;

	/** Runs before built-in key handling. Return true to skip the editing action. **/
	public var onKey:Null<KeyEvent->Bool> = null;

	/** Input interaction supplied by the view. Its disabled state prevents editing. **/
	public var interaction:Null<Interaction>;

	var stops:Array<CaretStop> = [{index: 0, x: 0, line: 0}];
	var measured:Null<String> = null;
	var measuredSize = 0.0;
	var measuredWidth = 0.0;

	/** Last measured line height. `lineCount` stores the number of measured lines. **/
	public var lineHeight(default, null) = 0.0;

	public var lines(default, null) = 1;

	/** Horizontal caret target preserved during vertical navigation. **/
	var goalX:Null<Float> = null;

	var dragging = false;
	var caretOn = true;
	var fadeId = 0;
	var blinkTimer:Null<ashui.animation.AnimationScheduler.Timer> = null;

	public function new(value:Signal<String>, multiline:Bool, wrapWidth:Float) {
		this.value = value;
		this.multiline = multiline;
		this.wrapWidth = wrapWidth;
		var fallback = ashui.theme.Themed.fontSize(TextSm);
		fontSize = Computed.make(() -> styledSize.get() == null ? fallback.get() : styledSize.get());
	}

	/** The existing CSS restyle notification updates metrics only when a font changes (git-bug e8a1b50). **/
	public function bindText(view:Text):Void {
		text = view;
		var identity = ashui.css.Identity.of(view.tree, view.node.id);
		byText.set(identity, this);
		if (!styledHook) {
			styledHook = true;
			ashui.css.Css.restyled.push(identity -> {
				var edit = byText.get(identity);
				if (edit != null)
					edit.restyled(identity);
			});
		}
		ashui.reactive.Owner.onCleanup(() -> byText.remove(identity));
	}

	function restyled(identity:ashui.css.Identity):Void {
		var size:Single = ashui.css.Css.fontSize(identity);
		var changed = size != styledSize.get();
		for (i in 0...FONT_FIELDS.length) {
			var value = ashui.css.Css.computed(identity, FONT_FIELDS[i]);
			if (fontFields[i] != value) {
				fontFields[i] = value;
				changed = true;
			}
		}
		if (!changed)
			return;
		styledSize.set(size);
		measured = null;
		geometry.set(geometry.get() + 1);
	}

	function set_wrapWidth(value:Float):Float {
		if (value != wrapWidth) {
			wrapWidth = value;
			measured = null;
			geometry.set(geometry.get() + 1);
		}
		return value;
	}

	// --- geometry ---

	/** Returns caret stops, cached per text value and font size. **/
	public function stopsFor(s:String):Array<CaretStop> {
		geometry.get();
		var size:Float = fontSize.get();
		if ((measured == s && measuredSize == size && measuredWidth == wrapWidth) || text == null)
			return stops;
		var key = s;
		s = masked(s);
		var capacity = s.length + 2;
		var out = new hl.Bytes(capacity * 12);
		var info = new hl.Bytes(16);
		var n = TextNative.blinc_text_carets(text.tree.ptr, text.node.id, ashui.core.Utf8.encode(s), size, wrapWidth, out, capacity, info);
		if (n > 0 && n <= capacity) {
			stops = [
				for (i in 0...n) {index: Std.int(out.getF32(i * 12)), x: out.getF32(i * 12 + 4), line: Std.int(out.getF32(i * 12 + 8))}
			];
			lineHeight = info.getF32(0);
			lines = Std.int(info.getF32(4));
			measured = key;
			measuredSize = size;
			measuredWidth = wrapWidth;
		}
		return stops;
	}

	/** Returns the caret stop at or before a string index. **/
	public function stopAt(i:Int, s:String):CaretStop {
		if (metrics != null) {
			prepareMetrics(s);
			return metrics.stopAt(i);
		}
		var list = stopsFor(s);
		var best = list[0];
		for (stop in list)
			if (stop.index <= i)
				best = stop;
		return best;
	}

	/** Returns the nearest caret index at `x` on a line, clamping to an existing line. **/
	public function indexAt(x:Float, line:Int):Int {
		if (metrics != null) {
			prepareMetrics(value.get());
			return metrics.indexAt(x, line);
		}
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

	/** Optional Y-to-line mapping for views with variable line heights. **/
	public var lineAtHeight:Null<Float->Int> = null;

	/** Returns the line at a text-local Y coordinate. **/
	public function lineAtY(y:Float):Int
		return lineAtHeight != null ? lineAtHeight(y) : lineHeight > 0 ? Std.int(Math.floor(y / lineHeight)) : 0;

	/** Returns line width from the final caret stop. **/
	public function lineWidth(line:Int):Float {
		if (metrics != null) {
			prepareMetrics(value.get());
			return metrics.lineWidth(line);
		}
		var w = 0.0;
		for (stop in stopsFor(value.get()))
			if (stop.line == line)
				w = Math.max(w, stop.x);
		return w;
	}

	/** Returns the previous or next caret stop around a string index. **/
	function step(i:Int, forward:Bool):Int {
		if (metrics != null) {
			prepareMetrics(value.get());
			return metrics.step(i, forward);
		}
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

	/** Finds the previous or next word boundary. **/
	function word(i:Int, forward:Bool):Int {
		// A password is one word, so moving by word gives nothing of it away.
		var s = masked(value.get());
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

	/** Returns the first or last caret stop on the line containing an index. **/
	function lineEdge(i:Int, end:Bool):Int {
		if (metrics != null) {
			prepareMetrics(value.get());
			return metrics.lineEdge(i, end);
		}
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

	/** Moves by `by` lines while preserving the horizontal caret target. **/
	function vertical(i:Int, by:Int):Int {
		var here = stopAt(i, value.get());
		if (goalX == null)
			goalX = here.x;
		var line = here.line + by;
		if (line < 0)
			return 0;
		if (metrics == null) stopsFor(value.get());
		if (line >= lines)
			return value.get().length;
		return indexAt(goalX, line);
	}

	function prepareMetrics(s:String):Void {
		metrics.prepare(s);
		lineHeight = metrics.lineHeight;
		lines = metrics.lines;
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

	/** Returns ordered selection offsets, with `from` before `to`. **/
	public function selectionRange():{from:Int, to:Int} {
		return {from: Std.int(Math.min(caret.get(), anchor.get())), to: Std.int(Math.max(caret.get(), anchor.get()))};
	}

	/** Returns the selected text. **/
	public function selection():String {
		var r = selectionRange();
		return value.get().substring(r.from, r.to);
	}

	/** Returns displayed text, including IME composition in place of the selection and any password mask. **/
	public function display():String {
		var c = composing.get();
		if (c == "")
			return masked(value.get());
		var r = selectionRange();
		var s = value.get();
		return masked(s.substr(0, r.from) + c + s.substr(r.to));
	}

	/** Applies one mask character per source character while preserving indices. Returns unmasked text when revealed. **/
	function masked(s:String):String
		return mask == null || revealed.get() ? s : StringTools.lpad("", mask, s.length);

	/** Returns the caret offset in displayed text, including the active composition. **/
	public function displayCaret():Int {
		var c = composing.get();
		if (c == "")
			return caret.get();
		return selectionRange().from + (composeCursor >= 0 ? composeCursor : c.length);
	}

	/** Returns the composition range in displayed text, or null when inactive. **/
	public function composedRange():Null<{from:Int, to:Int}> {
		var c = composing.get();
		if (c == "")
			return null;
		var from = selectionRange().from;
		return {from: from, to: from + c.length};
	}

	/** Updates IME composition. Empty composition text ends the composition after commit or cancellation. **/
	public function compose(e:CompositionEvent):Void {
		if (disabled() || readOnly)
			return;
		composeCursor = e.cursor;
		composing.set(e.text);
		restartBlink();
	}

	/** Replaces the selection and places the caret after the inserted text. **/
	public function replace(insert:String):Void {
		if (disabled() || readOnly) return;
		var s = value.get();
		var r = selectionRange();
		var next = s.substr(0, r.from) + insert + s.substr(r.to);
		if (next == s) { move(r.from + insert.length, false); return; }
		if (onBeforeInput != null) onBeforeInput();
		value.set(next);
		move(r.from + insert.length, false);
		if (onInput != null)
			onInput(next);
	}

	/** Deletes the selection, or the range between the caret and `to` when no selection exists. **/
	function erase(to:Int):Void {
		if (disabled() || readOnly) return;
		// Undo captures the user's caret before deletion expands its range (e53597f).
		var before = onBeforeInput;
		if (before != null) before();
		onBeforeInput = null;
		if (caret.get() == anchor.get())
			anchor.set(to);
		replace("");
		onBeforeInput = before;
	}

	function disabled():Bool
		return interaction != null && interaction.disabled.get();

	/** Inserts typed text over the selection. Converts line breaks to spaces for single-line editing. **/
	public function type(e:TextInputEvent):Void {
		if (disabled() || readOnly)
			return;
		var typed = accept == null ? e.text : accept(e.text);
		if (typed != "")
			replace(multiline ? typed : ~/\r\n|\r|\n/g.replace(typed, " "));
	}

	/** Handles key actions for navigation, selection, editing, clipboard, and submission. **/
	public function key(e:KeyEvent):Void {
		// The input method handles keys while it composes.
		if (disabled() || composing.get() != "")
			return;
		if (onKey != null && onKey(e))
			return;
		var mac = ashui.input.Keyboard.isMac();
		var byLine = e.superKey || (e.control && !mac);
		var at = caret.get();
		var selected = caret.get() != anchor.get();
		var length = value.get().length;
		switch e.key {
			case Named(ArrowLeft):
				move(byLine ? lineEdge(at, false) : e.alt ? word(at, false) : selected
					&& !e.shift ? selectionRange().from : step(at, false), e.shift);
			case Named(ArrowRight):
				move(byLine ? lineEdge(at, true) : e.alt ? word(at, true) : selected
					&& !e.shift ? selectionRange().to : step(at, true), e.shift);
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
				if (selected && mask == null)
					Clipboard.setText(selection());
			case Character(c) if ((c == "x" || c == "X") && (e.superKey || e.control)):
				if (selected && mask == null) {
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
				if (accept != null)
					pasted = accept(pasted);
				if (pasted != "" || selected)
					replace(pasted);
			case _:
				return;
		}
	}

	/** Prevents Space and Enter key releases from activating the surrounding view. **/
	public function keyUp(e:KeyEvent):Void {
		if (e.key.match(Named(Space) | Named(Enter)))
			e.preventDefault();
	}

	/**
		Handles a press in text-local coordinates. Shift extends the selection.
		Double-click selects a word; triple-click selects a paragraph. Dragging
		after either action extends selection in the same units.
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

	/** Extends a drag selection to text-local coordinates, using the selection unit chosen on press. **/
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

	/** Returns the word or paragraph containing an index for the current selection unit. **/
	function unit(i:Int):{from:Int, to:Int} {
		var s = masked(value.get());
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

	/** Ends pointer drag selection. **/
	public function release():Void {
		dragging = false;
	}

	/** Handles focus entering the view. **/
	public function focus():Void {
		focused.set(true);
		restartBlink();
	}

	/** Handles focus leaving: drops composition and collapses selection to the caret. **/
	public function blur():Void {
		focused.set(false);
		dragging = false;
		composing.set("");
		anchor.set(caret.get());
	}

	// --- caret blink ---

	/** Returns whether the caret should be drawn in the focused, active, visible window. **/
	public function showsCaret():Bool
		return focused.get() && ashui.input.WindowState.active.get() && ashui.input.WindowState.visible.get();

	/** Stops blinking and leaves the caret visible. **/
	public function stopBlink():Void {
		if (blinkTimer != null)
			blinkTimer.cancel();
		blinkTimer = null;
		fadeId++;
		caretOn = true;
		caretAlpha.set(1);
	}

	/** Shows the caret immediately and restarts blinking. **/
	public function restartBlink():Void {
		if (readOnly) { stopBlink(); return; }
		if (blinkTimer != null)
			blinkTimer.cancel();
		// Typing or moving shows the caret at once, with no fade.
		fadeId++;
		caretOn = true;
		caretAlpha.set(1);
		blinkTimer = ashui.animation.AnimationScheduler.main.after(BLINK, blink);
	}

	/** Begins the next caret fade and schedules the following blink while focused. **/
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

	/** Animates caret opacity over `FADE`, requesting frames only during the transition. **/
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

	/** Returns whether a blink callback is scheduled. Used by tests. **/
	@:noCompletion public function blinking():Bool
		return blinkTimer != null;
}
