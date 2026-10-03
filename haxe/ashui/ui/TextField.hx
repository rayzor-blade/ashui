package ashui.ui;

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
	/** HTML's input type, which CSS's `input[type=...]` sees: `text` by default; `password` shows dots and refuses copying. **/
	?type:String,
	/** Its width in layout units; the user-agent stylesheet's by default. **/
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
	everything, Command+C, X and V copy, cut and paste (see
	`ashui.input.Clipboard`), Escape gives focus up and Enter calls
	`onSubmit`. Clicking places the caret and dragging selects. A value
	longer than the field scrolls to keep the caret in view. `TextEditing`
	does the editing; `TextArea` is the many-line view of the same.

	It is the `<input>` of a text type: its look is the user-agent
	stylesheet's `input[type="text"]` (or the type given), with `:hover`,
	`:focus` and `:disabled`. Children are placed after the text, inside
	the box, as a number input's steppers are.
**/
class TextField extends Component<TextFieldProps> {
	/** Space kept between the clipped text and the field's inner edge, so a glyph or the caret at either end is not cut. **/
	static inline var INSET = 2.0;

	public var editing(default, null):TextEditing;

	final scroll = Signal.make((0 : Single));
	var box:Div;
	/** The part of the field the text shows through. **/
	var clip:Div;
	var text:Text;

	function render():Element {
		var e = editing = new TextEditing(props.value != null ? props.value : Signal.make(""), false, 0);
		var type = props.type != null ? props.type.toLowerCase() : "text";
		if (type == "password")
			e.mask = "\u2022";
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
		var stripLeft = Computed.make(() -> (INSET - scroll.get() : Single));
		text = new Text(shown, {wrap: false, fontSize: e.fontSize.get()});
		e.text = text;
		clip = hxx('<div class="relative grow h-full overflow-hidden">
					<div class="absolute top-0 bottom-0 flex flex-row items-center" left={stripLeft} width={4096}>
						<div class="relative">
							<div class="absolute top-0 bottom-0 bg-selection" left={selectionLeft} width={selectionWidth} />
							${text}
							<div class="absolute bottom-0 bg-text-primary" left={composedLeft} width={composedWidth} height={1} />
							<div class="absolute top-0" left={0}>
								<text class="text-sm text-text-tertiary" opacity={Computed.make(() -> (empty.get() ? 1 : 0 : Single))}>${placeholder}</text>
							</div>
							<div class="absolute top-0 bottom-0 bg-text-primary" left={caretLeft} width={1.5}
								opacity={Computed.make(() -> (e.showsCaret() ? e.caretAlpha.get() : 0 : Single))} />
						</div>
					</div>
				</div>');
		box = new Div({tag: "input"}, ([clip] : Array<Element>).concat(children));
		if (props.width != null)
			box.node.set(ashui.layout.Prop.Width, props.width);
		ashui.css.Identity.of(box.tree, box.node.id).setAttribute("type", type);
		text.node.set(ashui.layout.Prop.FontSize, e.fontSize);
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
		var value = editing.value.get();
		var end = editing.stopAt(value.length, value).x;
		s = Math.max(0, Math.min(s, Math.max(0, end - visible)));
		if (s != scroll.get())
			scroll.set(s);
	}

	/** `windowX` from the text's left edge; its bounds already include the scroll, which moves it by layout. **/
	function textX(windowX:Float):Float {
		var b = text.tree.getBounds(text.node);
		return b == null ? 0 : windowX - b.x;
	}
}
