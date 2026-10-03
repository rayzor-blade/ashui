package ashui.ui;

import ashui.input.Focus;
import ashui.input.Interaction;
import ashui.input.Scroll;
import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.reactive.Computed;
import ashui.reactive.Signal;
import ashui.reactive.Watch;
import ashui.ui.Hxx.hxx;

typedef TextAreaProps = {
	/** The text, read and written: the area sets it as the user edits. A signal of its own by default. **/
	?value:Signal<String>,
	/** Shown, dimmed, while the value is empty. **/
	?placeholder:String,
	?disabled:IntoReactive<Bool>,
	/** Its size in layout units; 320 by 120 by default. **/
	?width:Single,
	?height:Single,
	/** Called with the new value after each edit. **/
	?onInput:String->Void,
	/** Called with the value on Command+Enter (Control+Enter elsewhere). **/
	?onSubmit:String->Void
}

/**
	A text area: text of many lines, wrapped at its width, that scrolls when
	it is taller than the area. It edits as `TextField` does, and further:
	Enter starts a new line, Up and Down move between lines keeping to the
	same x, Page Up and Page Down move by the lines that fit, Home and End go
	to the ends of the line and Command with the arrows to the ends of the
	line or the text. Command+Enter calls `onSubmit`. A selection is drawn
	line by line. The caret is kept in view as it moves.
**/
class TextArea extends Component<TextAreaProps> {
	static inline var PADDING = 10.0;
	static inline var BORDER = 2.0;
	/** Room kept right of the text for the caret at the end of a full line. **/
	static inline var CARET_ROOM = 4.0;
	/** How far past a line's text a selection that runs on to the next line reaches. **/
	static inline var LINE_END = 5.0;

	public var editing(default, null):TextEditing;

	var box:Div;
	var text:Text;
	var scroller:Null<Scroll>;

	function render():Element {
		var width:Single = props.width != null ? props.width : 320;
		var height:Single = props.height != null ? props.height : 120;
		var wrapWidth:Single = width - 2 * (PADDING + BORDER) - CARET_ROOM;
		var e = editing = new TextEditing(props.value != null ? props.value : Signal.make(""), true, wrapWidth);
		e.onInput = props.onInput;
		e.onSubmit = props.onSubmit;
		var value = e.value;
		var shown = Computed.make(() -> e.display());
		var empty = Computed.make(() -> shown.get() == "");
		var placeholder = props.placeholder != null ? props.placeholder : "";
		// Each reads the font size too, so a theme change measures again.
		var caretStop = Computed.make(() -> {
			e.fontSize.get();
			e.stopAt(e.displayCaret(), shown.get());
		});
		var caretLeft = Computed.make(() -> (caretStop.get().x : Single));
		var caretTop = Computed.make(() -> (caretStop.get().line * e.lineHeight : Single));
		var lineHeight = Computed.make(() -> {
			caretStop.get();
			(e.lineHeight : Single);
		});
		// The selection hides while an input method composes in its place; the composition is underlined.
		var selection = Computed.make(() -> {
			e.fontSize.get();
			e.composing.get() != "" ? [] : selectionRects(e.caret.get(), e.anchor.get(), value.get());
		});
		var composed = Computed.make(() -> {
			var r = e.composedRange();
			if (r == null)
				[]
			else
				[for (rect in selectionRects(r.from, r.to, shown.get())) {x: rect.x, y: rect.y + rect.h - 1, w: rect.w, h: (1 : Single)}];
		});
		text = new Text(shown, {wrap: true, fontSize: e.fontSize.get()});
		e.text = text;
		box = hxx('
			<div class="flex flex-col rounded-lg bg-input-bg focus:bg-input-bg-focus disabled:bg-input-bg-disabled border-2 border-border hover:border-border-hover focus:border-border-focus disabled:border-border transition-colors overflow-y-auto"
				width={width} height={height} padding={PADDING} focusable={true}
				onPointerDown={p -> e.press(textX(p.x), textY(p.y), p.shift, p.clickCount)} onPointerMove={p -> e.drag(textX(p.x), textY(p.y))}
				onPointerUp={_ -> e.release()} onKeyDown={e.key} onKeyUp={e.keyUp} onTextInput={e.type} onComposition={e.compose}
				onFocus={_ -> e.focus()} onBlur={_ -> e.blur()}>
				<div class="relative shrink-0" width={wrapWidth}>
					<for {r in selection}>
						<div class="absolute bg-selection" left={r.x} top={r.y} width={r.w} height={r.h} />
					</for>
					${text}
					<for {r in composed}>
						<div class="absolute bg-text-primary" left={r.x} top={r.y} width={r.w} height={r.h} />
					</for>
					<div class="absolute top-0" left={0}>
						<text class="text-sm text-text-tertiary" opacity={Computed.make(() -> (empty.get() ? 1 : 0 : Single))}>${placeholder}</text>
					</div>
					<div class="absolute bg-text-primary" left={caretLeft} top={caretTop} width={1.5} height={lineHeight}
						opacity={Computed.make(() -> (e.showsCaret() ? e.caretAlpha.get() : 0 : Single))} />
				</div>
			</div>
		');
		text.node.set(ashui.layout.Prop.FontSize, e.fontSize);
		text.node.set(ashui.layout.Prop.Width, wrapWidth);
		e.interaction = Interaction.of(box.node);
		e.onEscape = () -> Focus.clear(box.tree);
		scroller = Scroll.of(box.node);
		e.pageLines = () -> e.lineHeight > 0 ? Std.int(Math.max(1, Math.floor((height - 2 * (PADDING + BORDER)) / e.lineHeight) - 1)) : 1;
		if (props.disabled != null)
			e.interaction.setDisabled(props.disabled);
		// Keeps the caret inside the visible part of the area.
		new Watch(() -> (caretTop.get() : Float), top -> reveal(top));
		// The blink stops while the window is in the background or hidden, and starts again on return.
		new Watch(() -> e.showsCaret(), on -> on ? e.restartBlink() : e.stopBlink());
		TextCaret.publish(e, () -> {
			var b = text.tree.getBounds(text.node);
			var scrollY = scroller != null ? scroller.y.get() : 0;
			b == null ? null : {x: b.x + caretLeft.get(), y: b.y + caretTop.get() - scrollY, width: 1.5, height: lineHeight.get()};
		});
		return box;
	}

	/** The selection as one rect per line it covers, in the text's coordinates. **/
	function selectionRects(caret:Int, anchor:Int, s:String):Array<{x:Single, y:Single, w:Single, h:Single}> {
		var e = editing;
		if (caret == anchor)
			return [];
		var from = e.stopAt(Std.int(Math.min(caret, anchor)), s);
		var to = e.stopAt(Std.int(Math.max(caret, anchor)), s);
		var lh = e.lineHeight;
		return [
			for (line in from.line...to.line + 1) {
				var x0 = line == from.line ? from.x : 0;
				var x1 = line == to.line ? to.x : e.lineWidth(line) + LINE_END;
				{x: (x0 : Single), y: (line * lh : Single), w: (Math.max(1, x1 - x0) : Single), h: (lh : Single)};
			}
		];
	}

	function reveal(caretTop:Float):Void {
		var bounds = box.tree.getBounds(box.node);
		if (scroller == null || bounds == null || editing.lineHeight <= 0)
			return;
		var view = bounds.height - 2 * BORDER;
		if (view <= 0)
			return;
		var top = PADDING + caretTop;
		var bottom = top + editing.lineHeight;
		var s = scroller.y.get();
		var to = s;
		if (top - PADDING < s)
			to = top - PADDING;
		else if (bottom + PADDING > s + view)
			to = bottom + PADDING - view;
		// The lines just measured, not the last layout, which may not have the newest line yet.
		var content = 2 * PADDING + editing.lines * editing.lineHeight;
		to = Math.max(0, Math.min(to, content - view));
		if (to != s)
			scroller.jumpTo(scroller.x.get(), to);
	}

	/** A window point from the text's top-left, scrolled content included. **/
	function textX(windowX:Float):Float {
		var b = text.tree.getBounds(text.node);
		return b == null ? 0 : windowX - b.x + (scroller != null ? scroller.x.get() : 0);
	}

	function textY(windowY:Float):Float {
		var b = text.tree.getBounds(text.node);
		return b == null ? 0 : windowY - b.y + (scroller != null ? scroller.y.get() : 0);
	}
}
