package ashui.ui;

import ashui.input.Focus;
import ashui.input.Interaction;
import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.reactive.Computed;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.reactive.Watch;

typedef TextFieldProps = {
	/** Editable text. Uses the supplied signal, or creates a local signal when omitted. **/
	?value:Signal<String>,
	/** Placeholder text shown while the value is empty. **/
	?placeholder:String,
	?disabled:IntoReactive<Bool>,
	/** Input type used by CSS `input[type="..."]`. Defaults to `text`; `password` masks text and disables copying. **/
	?type:String,
	/** Width in layout units. Defaults to the user-agent stylesheet width. **/
	?width:Single,
	/** Receives the new value after each edit. **/
	?onInput:String->Void,
	/** Receives the value when Enter is pressed. **/
	?onSubmit:String->Void,
	/** Shows password characters instead of dots while true. Copying remains disabled. **/
	?reveal:IntoReactive<Bool>
}

/**
	A single-line editor backed by `TextEditing`.
	Click or press Tab to focus it. Clicking places the caret; dragging
	selects text. Long values scroll horizontally to keep the caret visible.
	CSS `text-align` aligns the text, caret and selection together (d5a8df1).

	Keyboard controls:

	- Typing inserts text; Backspace and Delete remove it.
	- Arrows, Home and End move the caret. Hold Shift to select.
	- Alt moves by word. Command (Control elsewhere) moves to the ends.
	- Command+A selects all; Command+C, X and V copy, cut and paste.
	- Escape clears focus. Enter calls `onSubmit`.

	Text-type `<input>` elements use this component. The user-agent stylesheet
	styles `input[type="..."]` and its hover, focus and disabled states.
	Children appear inside the field after the text, such as number steppers.
	Use `TextArea` for multiline editing.
**/
class TextField extends Component<TextFieldProps> {
	/** Space between the text clipping region and the inner field edge, preventing clipped glyphs or carets. **/
	static inline var INSET = 2.0;

	public var editing(default, null):TextEditing;

	final scroll = Signal.make((0 : Single));
	final alignment = Signal.make((0 : Single));
	final placeholderLeft = Signal.make((0 : Single));
	var box:Div;
	/** Clipping region for the displayed text. **/
	var clip:Div;
	var text:Text;
	final hint = new Ref<Text>();
	var hintWidth = -1.0;
	var laidWidth = -1.0;
	static final layouts = new haxe.ds.ObjectMap<ashui.layout.LayoutTree, Array<TextField>>();
	static final hints = new haxe.ds.ObjectMap<ashui.css.Identity, TextField>();
	static var layoutHook = false;

	function render():Element {
		var e = editing = new TextEditing(props.value != null ? props.value : Signal.make(""), false, 0);
		var type = props.type != null ? props.type.toLowerCase() : "text";
		if (type == "password") {
			e.mask = "\u2022";
			switch (props.reveal : ashui.layout.IntoReactive.ReactiveType<Bool>) {
				case null:
				case Const(on):
					e.revealed.set(on);
				case Bound(signal):
					new Watch(() -> signal.get(), on -> e.revealed.set(on));
				case Derived(computed):
					new Watch(() -> computed.get(), on -> e.revealed.set(on));
			}
		}
		e.onInput = props.onInput;
		e.onSubmit = props.onSubmit;
		var value = e.value;
		var shown = Computed.make(() -> e.display());
		var empty = Computed.make(() -> shown.get() == "");
		var placeholder = props.placeholder != null ? props.placeholder : "";
		// Each reads the font size too, so a theme change measures again.
		var caretLeft = Computed.make(() -> {
			e.fontSize.get();
			(e.stopAt(e.displayCaret(), shown.get()).x : Single);
		});
		// The selection hides while an input method composes in its place.
		var selectionLeft = Computed.make(() -> {
			e.fontSize.get();
			(e.stopAt(e.selectionRange().from, value.get()).x : Single);
		});
		var selectionWidth = Computed.make(() -> {
			e.fontSize.get();
			var r = e.selectionRange();
			(e.composing.get() != "" ? 0 : e.stopAt(r.to, value.get()).x - e.stopAt(r.from, value.get()).x : Single);
		});
		// The composition is underlined, as input methods mark it.
		var composedLeft = Computed.make(() -> {
			var r = e.composedRange();
			(r == null ? 0 : e.stopAt(r.from, shown.get()).x : Single);
		});
		var composedWidth = Computed.make(() -> {
			var r = e.composedRange();
			(r == null ? 0 : e.stopAt(r.to, shown.get()).x - e.stopAt(r.from, shown.get()).x : Single);
		});
		var stripLeft = Computed.make(() -> (INSET + alignment.get() - scroll.get() : Single));
		text = new Text(shown, {wrap: false, fontSize: e.fontSize.get()});
		e.bindText(text);
		clip = <div class="relative grow h-full overflow-hidden">
			<div class="absolute top-0 bottom-0 flex flex-row items-center" left={stripLeft} width={4096}>
				<div class="relative">
					<div class="absolute top-0 bottom-0 bg-selection" left={selectionLeft} width={selectionWidth} />
					${text}
					<div class="absolute bottom-0 bg-text-primary" left={composedLeft} width={composedWidth} height={1} />
					<div class="absolute top-0" left={placeholderLeft}>
						<text ref={hint} class="text-text-tertiary" opacity={Computed.make(() -> (empty.get() ? 1 : 0 : Single))}>${placeholder}</text>
					</div>
					<div class="absolute top-0 bottom-0 bg-text-primary" left={caretLeft} width={1.5}
						opacity={Computed.make(() -> (e.showsCaret() ? e.caretAlpha.get() : 0 : Single))} />
				</div>
			</div>
		</div>;
		box = new Div({tag: "input"}, ([clip] : Array<Element>).concat(children));
		if (props.width != null)
			box.node.set(ashui.layout.Prop.Width, props.width);
		ashui.css.Identity.of(box.tree, box.node.id).setAttribute("type", type);
		var i = e.interaction = Interaction.of(box.node).setFocusable(true);
		i.onPointerDown(p -> e.press(textX(p.x), 0, p.shift, p.clickCount));
		i.onPointerMove(p -> e.drag(textX(p.x), 0));
		i.onPointerUp(_ -> e.release());
		i.onKeyDown(e.key);
		i.onKeyUp(e.keyUp);
		i.onTextInput(e.type);
		i.onComposition(e.compose);
		i.onFocus(_ -> e.focus());
		i.onBlur(_ -> e.blur());
		e.onEscape = () -> Focus.clear(box.tree);
		if (props.disabled != null)
			e.interaction.setDisabled(props.disabled);
		// Measure on layout changes only; release the registry with the component (git-bug d5a8df1).
		var tree = box.tree, fields = layouts.get(tree);
		if (fields == null) layouts.set(tree, fields = []);
		fields.push(this);
		var hintIdentity = ashui.css.Identity.of(tree, hint.get().node.id);
		if (placeholder != "") hints.set(hintIdentity, this);
		Owner.onCleanup(() -> {
			fields.remove(this);
			if (fields.length == 0) layouts.remove(tree);
			hints.remove(hintIdentity);
		});
		if (!layoutHook) {
			layoutHook = true;
			ashui.layout.LayoutTree.layoutHooks.push(tree -> {
				var fields = layouts.get(tree), changed = false;
				if (fields != null) for (field in fields) if (field.measureLayout()) changed = true;
				return changed;
			});
			ashui.css.Css.restyled.push(identity -> {
				var field = hints.get(identity);
				if (field != null) field.hintWidth = -1;
			});
		}
		// Keeps the caret inside the visible part of the field.
		new Watch(() -> caretLeft.get(), x -> reveal(x));
		// The blink stops while the window is in the background or hidden, and starts again on return.
		new Watch(() -> e.showsCaret(), on -> on ? e.restartBlink() : e.stopBlink());
		TextCaret.publish(e, () -> {
			var b = text.tree.getBounds(text.node);
			b == null ? null : {x: b.x + caretLeft.get(), y: b.y, width: 1.5, height: b.height};
		});
		return box;
	}

	/** CSS alignment moves text, selection and caret together; overflow still scrolls (git-bug d5a8df1). **/
	function measureLayout():Bool {
		var b = clip.tree.getBounds(clip.node);
		if (b == null || b.width <= 2 * INSET) return false;
		var visible = b.width - 2 * INSET;
		var factor = switch (text.tree.textAlign(text.node.id)) {
			case ashui.types.Style.TextAlign.Center: 0.5;
			case ashui.types.Style.TextAlign.Right: 1.0;
			case _: 0.0;
		};
		// Left-aligned fields already follow the caret watch; unchanged layout needs no extra text measurement (d5a8df1).
		if (factor == 0 && alignment.get() == 0 && placeholderLeft.get() == 0 && laidWidth == b.width) return false;
		laidWidth = b.width;
		var shown = editing.display();
		var offset:Single = 0, placeholderOffset:Single = 0;
		if (factor != 0) {
			// Rounded bounds depend on the text's position and can oscillate after centering (git-bug d5a8df1).
			var advance = editing.stopAt(shown.length, shown).x;
			offset = factor * Math.max(0, visible - advance);
			if (props.placeholder != null && props.placeholder != "")
				placeholderOffset = factor * Math.max(0, visible - placeholderWidth()) - offset;
		}
		var changed = offset != alignment.get() || placeholderOffset != placeholderLeft.get();
		if (offset != alignment.get()) alignment.set(offset);
		if (placeholderOffset != placeholderLeft.get()) placeholderLeft.set(placeholderOffset);
		var previous = scroll.get();
		reveal(editing.stopAt(editing.displayCaret(), shown).x);
		return changed || previous != scroll.get();
	}

	/** Measure the placeholder once in its own styled font; retain fractional advances (git-bug d5a8df1). **/
	function placeholderWidth():Float {
		var value = props.placeholder;
		if (value == null || value == "") return 0;
		if (hintWidth < 0) {
			var capacity = value.length + 2, out = new hl.Bytes(capacity * 12), info = new hl.Bytes(16);
			var count = ashui.core.externs.TextNative.blinc_text_carets(box.tree.ptr, hint.get().node.id,
				ashui.core.Utf8.encode(value), 0, 0, out, capacity, info);
			hintWidth = count > 0 && count <= capacity ? out.getF32((count - 1) * 12 + 4) : 0;
		}
		return hintWidth;
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
		var value = editing.display();
		var end = editing.stopAt(value.length, value).x;
		s = Math.max(0, Math.min(s, Math.max(0, end - visible)));
		if (s != scroll.get())
			scroll.set(s);
	}

	/** Converts a window X coordinate to text coordinates. Text bounds already include scrolling. **/
	function textX(windowX:Float):Float {
		var b = text.tree.getBounds(text.node);
		return b == null ? 0 : windowX - b.x;
	}
}
