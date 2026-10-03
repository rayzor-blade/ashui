package ashui.ui;

import ashui.core.externs.TextNative;
import ashui.input.Events;
import ashui.input.Focus;
import ashui.input.Interaction;
import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.reactive.Computed;
import ashui.reactive.Signal;
import ashui.reactive.Watch;
import ashui.ui.Hxx.hxx;

typedef TextFieldProps = {
	/** The text, read and written: the field sets it as the user edits. A signal of its own by default. **/
	?value:Signal<String>,
	/** Shown, dimmed, while the value is empty. **/
	?placeholder:String,
	?disabled:IntoReactive<Bool>,
	/** Its width in layout units; 240 by default. **/
	?width:Single,
	/** Called with the new value after each edit. **/
	?onInput:String->Void,
	/** Called with the value when Enter is pressed. **/
	?onSubmit:String->Void
}

/**
	A single-line text field. Clicking or tabbing to it gives it focus; then
	typing inserts at the caret, Backspace and Delete remove, the arrows,
	Home and End move the caret, Shift with any of them selects, Alt moves
	by word and Command (Control elsewhere) to the ends, Command+A selects
	everything, Escape gives focus up and Enter calls `onSubmit`. Clicking
	places the caret and dragging selects. A value longer than the field
	scrolls to keep the caret in view.

	Indices are positions in the Haxe string; the caret stands only on
	character boundaries, which the text engine reports for the field's font.
**/
class TextField extends Component<TextFieldProps> {
	/** Space kept between the clipped text and the field's inner edge, so a glyph or the caret at either end is not cut. **/
	static inline var INSET = 2.0;

	/** Seconds the caret shows, then hides, while the field has focus. **/
	static inline var BLINK = 0.53;

	var value:Signal<String>;
	final focused = Signal.make(false);
	/** Where the caret is, and where the selection started; equal when nothing is selected. **/
	final caret = Signal.make(0);
	final anchor = Signal.make(0);
	final scroll = Signal.make((0 : Single));
	final caretShown = Signal.make(true);
	var dragging = false;
	var blinkTime = 0.0;
	var blinking = false;

	var box:Div;
	/** The part of the field the text shows through. **/
	var clip:Div;
	var text:Text;
	var interaction:Interaction;
	/** Caret stops for the current value: string index, then x. **/
	var stops:Array<{index:Int, x:Float}> = [{index: 0, x: 0}];
	/** The value and font size `stops` were measured for. **/
	var measured:Null<String> = null;
	var measuredSize = 0.0;
	var fontSize:Computed<Single>;

	function render():Element {
		value = props.value != null ? props.value : Signal.make("");
		var width:Single = props.width != null ? props.width : 240;
		var empty = Computed.make(() -> value.get() == "");
		var placeholder = props.placeholder != null ? props.placeholder : "";
		// Each reads the font size too, so a theme change measures again.
		var caretLeft = Computed.make(() -> {
			fontSize.get();
			(xAt(caret.get(), value.get()) : Single);
		});
		var selectionLeft = Computed.make(() -> {
			fontSize.get();
			(xAt(Std.int(Math.min(caret.get(), anchor.get())), value.get()) : Single);
		});
		var selectionWidth = Computed.make(() -> {
			fontSize.get();
			(Math.abs(xAt(caret.get(), value.get()) - xAt(anchor.get(), value.get())) : Single);
		});
		var stripLeft = Computed.make(() -> (INSET - scroll.get() : Single));
		fontSize = ashui.theme.Themed.fontSize(TextSm);
		text = new Text(value, {wrap: false, fontSize: fontSize.get()});
		var clip:Div = null;
		box = hxx('
			<div class="flex flex-row items-center px-2.5 rounded-lg bg-input-bg focus:bg-input-bg-focus disabled:bg-input-bg-disabled border-2 border-border hover:border-border-hover focus:border-border-focus disabled:border-border transition-colors"
				width={width} height={38} focusable={true}
				onPointerDown={press} onPointerMove={drag} onPointerUp={_ -> dragging = false}
				onKeyDown={key} onKeyUp={keyUp} onTextInput={type}
				onFocus={_ -> { focused.set(true); restartBlink(); }}
				onBlur={_ -> { focused.set(false); dragging = false; anchor.set(caret.get()); }}>
				${clip = hxx('<div class="relative grow h-full overflow-hidden">
					<div class="absolute top-0 bottom-0 flex flex-row items-center" left={stripLeft} width={4096}>
						<div class="relative">
							<div class="absolute top-0 bottom-0 bg-selection" left={selectionLeft} width={selectionWidth} />
							${text}
							<div class="absolute top-0" left={0}>
								<text class="text-sm text-text-tertiary" opacity={Computed.make(() -> (empty.get() ? 1 : 0 : Single))}>${placeholder}</text>
							</div>
							<div class="absolute top-0 bottom-0 bg-text-primary" left={caretLeft} width={1.5}
								opacity={Computed.make(() -> (focused.get() && caretShown.get() ? 1 : 0 : Single))} />
						</div>
					</div>
				</div>')}
			</div>
		');
		this.clip = clip;
		text.node.set(ashui.layout.Prop.FontSize, fontSize);
		interaction = Interaction.of(box.node);
		if (props.disabled != null)
			interaction.setDisabled(props.disabled);
		// Keeps the caret inside the visible part of the field.
		new Watch(() -> caretLeft.get(), x -> reveal(x));
		return box;
	}

	// --- geometry ---

	/** The caret stops of `s`, from the text engine, measured once per value. **/
	function stopsFor(s:String):Array<{index:Int, x:Float}> {
		var size:Float = fontSize.get();
		if ((measured == s && measuredSize == size) || text == null)
			return stops;
		var capacity = s.length + 2;
		var out = new hl.Bytes(capacity * 12);
		var n = TextNative.blinc_text_carets(text.tree.ptr, text.node.id, ashui.core.Utf8.encode(s), size, out, capacity);
		if (n > 0 && n <= capacity) {
			stops = [for (i in 0...n) {index: Std.int(out.getF32(i * 12)), x: out.getF32(i * 12 + 4)}];
			measured = s;
			measuredSize = size;
		}
		return stops;
	}

	/** The x of the caret before string index `i` in `s`. **/
	function xAt(i:Int, s:String):Float {
		var best = 0.0;
		for (stop in stopsFor(s))
			if (stop.index <= i)
				best = stop.x;
		return best;
	}

	/** The caret stop nearest `x` in the current value. **/
	function indexAt(x:Float):Int {
		var best = 0;
		var distance = Math.POSITIVE_INFINITY;
		for (stop in stopsFor(value.get())) {
			var d = Math.abs(stop.x - x);
			if (d < distance) {
				distance = d;
				best = stop.index;
			}
		}
		return best;
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

	function reveal(x:Float):Void {
		var bounds = clip.tree.getBounds(clip.node);
		if (bounds == null)
			return;
		var visible = bounds.width - 2 * INSET;
		// Not laid out yet: there is nothing to scroll within.
		if (visible <= 0)
			return;
		var s = scroll.get();
		if (x - s > visible)
			s = x - visible;
		else if (x < s)
			s = x;
		// Never past the start, nor further than the text overflows.
		var end = xAt(value.get().length, value.get());
		s = Math.max(0, Math.min(s, Math.max(0, end - visible)));
		if (s != scroll.get())
			scroll.set(s);
	}

	// --- editing ---

	function move(to:Int, select:Bool):Void {
		caret.set(to);
		if (!select)
			anchor.set(to);
		restartBlink();
	}

	/** Replaces the selection with `insert`, leaving the caret after it. **/
	function replace(insert:String):Void {
		var s = value.get();
		var from = Std.int(Math.min(caret.get(), anchor.get()));
		var to = Std.int(Math.max(caret.get(), anchor.get()));
		var next = s.substr(0, from) + insert + s.substr(to);
		value.set(next);
		move(from + insert.length, false);
		if (props.onInput != null)
			props.onInput(next);
	}

	/** Deletes the selection, or from the caret to `to` when nothing is selected. **/
	function erase(to:Int):Void {
		if (caret.get() == anchor.get())
			anchor.set(to);
		replace("");
	}

	function type(e:TextInputEvent):Void {
		if (!interaction.disabled.get())
			replace(e.text);
	}

	function key(e:KeyEvent):Void {
		if (interaction.disabled.get())
			return;
		var byLine = e.superKey || (e.control && !isMac());
		var at = caret.get();
		var selected = caret.get() != anchor.get();
		switch e.key {
			case Named(ArrowLeft):
				move(byLine ? 0 : e.alt ? word(at, false) : selected && !e.shift ? Std.int(Math.min(at, anchor.get())) : step(at, false), e.shift);
			case Named(ArrowRight):
				move(byLine ? value.get().length : e.alt ? word(at, true) : selected && !e.shift ? Std.int(Math.max(at, anchor.get())) : step(at, true), e.shift);
			case Named(Home) | Named(ArrowUp):
				move(0, e.shift);
			case Named(End) | Named(ArrowDown):
				move(value.get().length, e.shift);
			case Named(Backspace):
				erase(byLine ? 0 : e.alt ? word(at, false) : step(at, false));
			case Named(Delete):
				erase(byLine ? value.get().length : e.alt ? word(at, true) : step(at, true));
			case Named(Escape):
				Focus.clear(box.tree);
			case Named(Enter):
				e.preventDefault();
				if (props.onSubmit != null)
					props.onSubmit(value.get());
			case Named(Space):
				// Typed as text; it must not click the field as well.
				e.preventDefault();
			case Character(c) if ((c == "a" || c == "A") && (e.superKey || e.control)):
				anchor.set(0);
				move(value.get().length, true);
			case _:
				return;
		}
	}

	function keyUp(e:KeyEvent):Void {
		if (e.key.match(Named(Space) | Named(Enter)))
			e.preventDefault();
	}

	function press(e:PointerEvent):Void {
		if (interaction.disabled.get())
			return;
		var at = indexAt(textX(e.x));
		move(at, e.shift);
		dragging = true;
	}

	function drag(e:PointerEvent):Void {
		if (dragging && interaction.pressed.get())
			move(indexAt(textX(e.x)), true);
	}

	/** `windowX` from the text's left edge. **/
	function textX(windowX:Float):Float {
		var b = text.tree.getBounds(text.node);
		return b == null ? 0 : windowX - b.x;
	}

	// --- caret blink ---

	function restartBlink():Void {
		blinkTime = 0;
		caretShown.set(true);
		if (blinking)
			return;
		blinking = true;
		ashui.animation.AnimationScheduler.main.addTicker(dt -> {
			if (!focused.get()) {
				blinking = false;
				caretShown.set(true);
				return false;
			}
			blinkTime += dt;
			var on = Std.int(blinkTime / BLINK) % 2 == 0;
			if (on != caretShown.get())
				caretShown.set(on);
			return true;
		});
	}

	static inline function isMac():Bool
		return Sys.systemName() == "Mac";
}
