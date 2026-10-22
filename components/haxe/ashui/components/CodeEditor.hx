package ashui.components;

import ashui.components.code.CodeAnnotations;
import ashui.components.code.CodeAnnotations.CodeDecoration;
import ashui.components.code.CodeAnnotations.CodeMarker;
import ashui.components.code.CodeCompletions;
import ashui.components.code.CodeCompletions.CodeCompletion;
import ashui.components.code.CodeDocument;
import ashui.components.code.CodeDocument.CodeLine;
import ashui.components.code.CodeHighlighter;
import ashui.components.code.CodeHints;
import ashui.components.code.CodeHints.CodeHint;
import ashui.components.code.CodeHints.CodeRect;
import ashui.components.code.CodeHistory;
import ashui.components.code.CodeEditorState;
import ashui.components.code.CodeHistory.CodeEdit;
import ashui.components.code.CodeHistory.CodePatch;
import ashui.components.code.CodeMetrics;
import ashui.components.code.CodeFind;
import ashui.components.code.CodeMinimap;
import ashui.components.code.CodeSyntax;
import ashui.css.Css;
import ashui.css.Identity;
import ashui.input.Events;
import ashui.input.Focus;
import ashui.input.Interaction;
import ashui.input.Scroll;
import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.layout.LayoutTree;
import ashui.reactive.Computed;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.reactive.Watch;
import ashui.state.Machine;
import ashui.ui.Component;
import ashui.svg.SvgDocument;
import ashui.ui.Div;
import ashui.ui.Svg;
import ashui.ui.Text;
import ashui.ui.TextCaret;
import ashui.ui.TextEditing;

typedef CodeEditorProps = {
	/** Persistent document/history/navigation data. Use instead of `value` to release and recreate the view. **/
	?state:CodeEditorState,
	/** A shared signal, initial string, or derived source. Line endings should be LF. **/
	?value:IntoReactive<String>,
	/** haxe/hxx, javascript/js/jsx, typescript/ts/tsx, rust, json, css, python/py, lua or plain. **/
	?language:IntoReactive<String>,
	/** An application grammar, in place of the built-in lexical highlighter. **/
	?highlighter:CodeHighlighter,
	?lineNumbers:Bool,
	?folding:Bool,
	?indentGuides:Bool,
	/** Highlight the matching pair next to a caret or pointer selection. **/
	?highlightBrackets:Bool,
	/** A strip down the right edge that draws the whole document scaled down, with a slider over what is on screen; pressing it, dragging the slider or the wheel over it scroll the editor. **/
	?minimap:Bool,
	/** Reserves a slot in the gutter, left of the line numbers, for what `markers` puts there and where a press calls `onGutterClick`. **/
	?gutterMarkers:Bool,
	/** Asked for a hint about the character at an offset once the pointer has rested on it; what it returns opens in a popover, and null leaves the popover to the titles of the decorations there. **/
	?hover:Int->Null<CodeHint>,
	/** Definition navigation at a text offset on Command-click (macOS) or Control-click; handled before selection. **/
	?onNavigate:Int->Void,
	/** Seconds the pointer rests on a character before `hover` is asked, 0.45 by default. **/
	?hintDelay:Float,
	/** The widest the minimap gets, 96 by default; it is a quarter of the editor's width when that is less. **/
	?minimapWidth:Float,
	/** Spaces per tab stop and indentation level, 4 by default. **/
	?tabSize:Int,
	/** Insert spaces for Tab by default; false inserts a tab character. **/
	?insertSpaces:Bool,
	?readOnly:IntoReactive<Bool>,
	?disabled:IntoReactive<Bool>,
	?onInput:String->Void,
	?onSubmit:String->Void,
	/** Called with each key press before the editor handles it; return true to keep the editor from it, as for F2, F12 or Ctrl+Space. It does not stop the event reaching others: `preventDefault` does that. **/
	?onKey:KeyEvent->Bool,
	/** Handle the built-in find/replace shortcuts, true by default. Apps may use showFind/findNext with their own bindings. **/
	?findShortcuts:Bool,
	/** Accessible name for the editing surface. **/
	?label:String,
	?id:String
}

private enum CodePhase { Resting; Selecting; }
private enum CodeEvent { Press; Release; Blur; }
private typedef Run = {text:String, kind:String, x:Single};
private typedef Row = {line:CodeLine, source:Int, row:Int, top:Single, runs:Array<Run>, byKind:Map<String, Array<Run>>, width:Single, guides:Array<Single>, stamp:Int, tokens:Int};
/** A pooled token element: the `index`th run of its `kind` in the row its slot shows. **/
private typedef Token = {kind:String, index:Int};
/** A decoration's mark on one row. **/
private typedef DecorationBox = {x:Single, top:Single, width:Single, height:Single, className:String};

/**
	A virtualized code editor, built from Ashui text, buttons and scrolling
	(e53597f). The shared TextEditing engine handles grapheme navigation,
	clipboard, selection and IME. This view adds line highlighting, folding,
	indentation and bounded undo/redo. All appearance is components.css.
**/
class CodeEditor extends Component<CodeEditorProps> {
	public var value(default, null):Signal<String>;
	public var state(default, null):CodeEditorState;
	public var editing(default, null):TextEditing;
	public var document(default, null):CodeDocument;
	public var scroll(default, null):Scroll;
	public var metrics(default, null):CodeMetrics;
	/** What the app marks in the text and gutter; `decorate` and `markers` are its way in. **/
	public var annotations(default, null):CodeAnnotations;
	public var search(default, null):CodeFind;
	var hints:Null<CodeHints> = null;
	var completions:Null<CodeCompletions> = null;
	var gutterNow:Void->Float = () -> 0;
	/** Called with a line, from 0, and the press, when the gutter's marker slot is pressed, whether or not the line has a marker (`gutterMarkers`). **/
	public var onGutterClick:Null<(Int, ashui.input.Events.PointerEvent)->Void> = null;
	final revision = Signal.make(0);
	final viewHeight = Signal.make(320.0);
	final viewWidth = Signal.make(600.0);
	final boxWidth = Signal.make(600.0);
	var history(get, never):CodeHistory;
	inline function get_history():CodeHistory return state.history;
	var pane:Div;
	var probe:Text;
	var cachedRows:Array<Row> = [];
	// The row elements are pooled: row `r` of the document is shown by slot `r % capacity`, so scrolling a line changes the
	// bindings of the one slot whose row changed and builds nothing.
	final slotRows:Array<Signal<Null<Row>>> = [];
	final shownRows:Array<Null<Row>> = [];
	// A slot's token elements are pooled by kind, so a row taking a slot changes text and position and never a token's kind, which
	// would restyle it: `slotPools` holds the elements of each kind, `slotKinds` the kinds in the order first met.
	final slotTokens:Array<Signal<Array<Token>>> = [];
	final slotPools:Array<Map<String, Array<Token>>> = [];
	final slotKinds:Array<Array<String>> = [];
	var oldText = "";
	var oldSelection:CodeSelection;
	var knownValue(get, set):String;
	inline function get_knownValue():String return state.knownValue;
	inline function set_knownValue(next:String):String return state.knownValue = next;
	var tabSize = 4;
	var lastFont = "";
	var fontRevision = 0;
	var fontDirty = true;
	var phase:Machine<CodePhase, CodeEvent>;
	static inline var PAD = 12.0;

	/** The gutter's marker slot, in layout units. **/
	static inline var MARKER = 18.0;

	/** The width of one wave of a squiggle. **/
	static inline var SQUIGGLE = 4.0;

	/** CodeView keeps the same selection and scrolling behavior without editing. **/
	function editable():Bool return true;

	function render():Element {
		Library.use();
		if (props.state != null && props.value != null) throw "CodeEditor accepts state or value, not both";
		value = props.state != null ? props.state.value : switch props.value {
			case null: Signal.make("");
			case Const(v): Signal.make(v);
			case Bound(s): s;
			case Derived(c): var s = Signal.make(c.get()); new Watch(() -> c.get(), v -> s.set(v)); s;
		}
		state = props.state == null ? new CodeEditorState(value) : props.state;
		var stateToken = state.resume();
		if (knownValue != value.get()) { history.clear(); knownValue = value.get(); }
		var language:IntoReactive<String> = props.language == null ? "plain" : props.language;
		var syntax = () -> props.highlighter != null ? props.highlighter : CodeSyntax.forLanguage(read(language));
		tabSize = Std.int(Math.max(1, Math.min(16, props.tabSize == null ? 4 : props.tabSize)));
		if (state.document == null) {
			state.document = new CodeDocument(value.get(), syntax());
			state.annotations = new CodeAnnotations(state.document);
		}
		document = state.document;
		annotations = state.annotations;
		metrics = new CodeMetrics(document, syntax(), tabSize);
		var e = editing = new TextEditing(value, true, 0);
		e.metrics = metrics;
		probe = new Text("", {wrap: false});
		Identity.of(probe.tree, probe.node.id).addClasses(["ui-code-text", "ui-code-probe"]);
		metrics.text = probe;
		e.bindText(probe);
		e.caret.set(Std.int(Math.min(value.get().length, state.caret)));
		e.anchor.set(Std.int(Math.min(value.get().length, state.anchor)));
		knownValue = value.get();
		e.onBeforeInput = () -> { oldText = value.get(); oldSelection = {caret: e.caret.get(), anchor: e.anchor.get()}; };
		e.onInput = next -> {
			history.record(oldText, next, oldSelection, {caret: e.caret.get(), anchor: e.anchor.get()});
			oldText = "";
			knownValue = next;
			if (props.onInput != null) props.onInput(next);
		};
		e.onSubmit = props.onSubmit;
		e.onKey = event -> (completions != null && completions.key(event)) || (props.onKey != null && props.onKey(event)) || codeKey(event);
		e.accept = s -> ~/\r\n|\r/g.replace(s, "\n");
		phase = new Machine<CodePhase, CodeEvent>(Resting, (state, event) -> switch [state, event] {
			case [_, Press]: Selecting;
			case [_, Release] | [_, Blur]: Resting;
		});
		phase.onExit(Selecting, _ -> e.release());
		var readOnly = Computed.make(() -> !editable() || (props.readOnly != null && read(props.readOnly)));
		new Watch(() -> readOnly.get(), on -> e.readOnly = on);
		new Watch(() -> { var content = e.display(); var highlighter = syntax(); {content: content, highlighter: highlighter}; }, next -> {
			if (knownValue != value.get()) { history.clear(); oldText = ""; knownValue = value.get(); }
			metrics.syntax = next.highlighter;
			metrics.prepare(next.content);
			if (state.annotatedText != value.get()) { annotations.edited(state.annotatedText, value.get()); state.annotatedText = value.get(); }
			var length = value.get().length;
			if (e.caret.get() > length) e.caret.set(length);
			if (e.anchor.get() > length) e.anchor.set(length);
			refresh();
		}, (a, b) -> a.content == b.content && a.highlighter == b.highlighter);

		search = new CodeFind(this, () -> !readOnly.get() && (e.interaction == null || !e.interaction.disabled.get()), props.findShortcuts != false);

		var rowHeight = Computed.make(() -> { revision.get(); (metrics.lineHeight : Single); });
		var gutter = Computed.make(() -> {
			revision.get();
			(props.lineNumbers == false ? 0 : Std.string(document.lines.length).length * metrics.characterWidth + 18)
				+ (props.folding == false ? 0 : 22) + (props.lineNumbers == false && props.folding == false ? 0 : 8) + (props.gutterMarkers == true ? MARKER : 0);
		});
		var contentHeight = Computed.make(() -> { revision.get(); (PAD * 2 + document.visible.length * metrics.lineHeight : Single); });
		var contentWidth = Computed.make(() -> {
			revision.get();
			var widest = 0;
			for (source in document.visible) {
				var column = 0;
				for (i in 0...document.lines[source].text.length) column += document.lines[source].text.charAt(i) == "\t" ? tabSize - column % tabSize : 1;
				widest = Std.int(Math.max(widest, column));
			}
			(Math.max(viewWidth.get(), gutter.get() + PAD * 2 + widest * metrics.characterWidth + 2) : Single);
		});
		// The window's rows as signals, set only when one changes, so a scroll inside the window runs nothing (a computed passes on every run).
		var firstRow = Signal.make(0), endRow = Signal.make(0);
		new Watch(() -> windowStart(), row -> firstRow.set(row));
		new Watch(() -> windowEnd(), row -> endRow.set(row));
		var rows = Computed.make(() -> visibleRows(firstRow.get(), endRow.get()));
		// A short or folded document needs no slots beyond its visible lines.
		var capacity = Computed.make(() -> {
			revision.get();
			var window = Std.int(Math.ceil((viewHeight.get() + PAD) / Math.max(1, metrics.lineHeight))) + 9;
			(Std.int(Math.max(1, Math.min(document.visible.length, window))) : Int);
		});
		var slots = Computed.make(() -> [for (i in 0...capacity.get()) i]);
		new Watch(() -> { capacity.get(); rows.get(); }, _ -> distribute(rows.get(), capacity.get()));
		var caret = Computed.make(() -> {
			revision.get(); e.fontSize.get();
			e.stopAt(e.displayCaret(), e.display());
		});
		var selections = Computed.make(() -> {
			revision.get();
			var range = e.composing.get() == "" ? e.selectionRange() : e.composedRange();
			var result:Array<{x:Single, top:Single, width:Single, height:Single}> = [];
			if (range != null && range.from != range.to) for (row in rows.get()) {
				var line = row.line, end = line.start + line.text.length;
				if (range.to <= line.start || range.from > end) continue;
				var x = metrics.xAt(line, Std.int(Math.max(0, range.from - line.start)));
				var right = range.to > end ? row.width + metrics.characterWidth : metrics.xAt(line, range.to - line.start);
				var composition = e.composing.get() != "";
				result.push({x: (gutter.get() + PAD + x : Single), top: (row.top + (composition ? metrics.lineHeight - 2 : 0) : Single), width: (Math.max(2, right - x) : Single), height: (composition ? 1 : metrics.lineHeight : Single)});
			}
			result;
		});
		// A mark for each row a decoration touches, kept from one build to the next while its place is the same, so a scroll does not rebuild it.
		var boxes = new Map<String, DecorationBox>();
		var decorationBoxes = Computed.make(() -> {
			revision.get(); annotations.revision.get();
			var list = annotations.decorations(), result:Array<DecorationBox> = [], kept = new Map<String, DecorationBox>();
			if (list.length > 0) for (row in rows.get()) {
				var line = row.line, end = line.start + line.text.length;
				for (d in list) {
					var whole = d.wholeLine == true, empty = d.to <= d.from;
					if (whole ? (empty ? d.from < line.start || d.from > end : d.to <= line.start || d.from > end) : (empty || d.to <= line.start || d.from > end)) continue;
					var x = whole ? 0 : gutter.get() + PAD + metrics.xAt(line, Std.int(Math.max(0, d.from - line.start)));
					var right = whole ? contentWidth.get() : d.to > end ? gutter.get() + PAD + row.width + metrics.characterWidth : gutter.get() + PAD + metrics.xAt(line, d.to - line.start);
					var key = d.className + "|" + row.row + "|" + x + "|" + right;
					var box = boxes.get(key);
					if (box == null) box = {x: (x : Single), top: row.top, width: (Math.max(2, right - x) : Single), height: (metrics.lineHeight : Single), className: d.className};
					kept.set(key, box);
					result.push(box);
				}
			}
			boxes = kept;
			result;
		});
		var matches = Computed.make(() -> {
			revision.get();
			var result:Array<{x:Single, top:Single, width:Single}> = [];
			if (props.highlightBrackets == false || !e.focused.get() || e.composing.get() != "" || e.caret.get() != e.anchor.get()) return result;
			for (index in document.matchingBrackets(e.caret.get())) {
				var source = document.lineAt(index), row = document.rows[source], line = document.lines[source];
				if (document.visible[row] != source) continue;
				var x = metrics.xAt(line, index - line.start), end = metrics.xAt(line, index - line.start + 1);
				result.push({x: (gutter.get() + PAD + x : Single), top: (PAD + row * metrics.lineHeight : Single), width: (Math.max(2, end - x) : Single)});
			}
			return result;
		});
		var searchMarks = new Map<String, DecorationBox>();
		var searchBoxes = Computed.make(() -> {
			var found = search.result.get(), range = e.selectionRange(), result:Array<DecorationBox> = [], kept = new Map<String, DecorationBox>();
			for (row in rows.get()) {
				var line = row.line, end = line.start + line.text.length, index = found.lowerBound(line.start);
				if (index > 0 && found.matches[index-1].to > line.start) index--;
				while (index < found.matches.length) {
					var m = found.matches[index++]; if (m.from > end) break;
					if (m.to < line.start || (m.to == line.start && m.from != m.to)) continue;
					var x = gutter.get() + PAD + metrics.xAt(line, Std.int(Math.max(0, m.from-line.start)));
					var right = m.to > end ? gutter.get()+PAD+row.width+metrics.characterWidth : gutter.get()+PAD+metrics.xAt(line,m.to-line.start);
					var selected = range.from == m.from && range.to == m.to;
					var key = row.row+"|"+m.from+"|"+m.to+"|"+x+"|"+right+"|"+metrics.lineHeight+"|"+selected;
					var mark = searchMarks.get(key);
					if (mark == null) mark = {x:(x:Single),top:row.top,width:(Math.max(2,right-x):Single),height:(metrics.lineHeight:Single),className:selected ? "ui-code-find-mark ui-code-find-current" : "ui-code-find-mark"};
					kept.set(key,mark); result.push(mark);
				}
			}
			searchMarks = kept;
			result;
		});
		var content = <div class="ui-code-content" width={contentWidth} height={contentHeight}>
			${probe}
			<div class="ui-code-active-line" top={Computed.make(() -> (PAD + caret.get().line * metrics.lineHeight : Single))}
				left={0} width={contentWidth} height={rowHeight} opacity={Computed.make(() -> (e.focused.get() ? 1 : 0 : Single))} />
			<for {b in searchBoxes}>${new Div({classes:b.className.split(" "), left:b.x, top:b.top, width:b.width, height:b.height})}</for>
			<for {b in decorationBoxes}>{decorationMark(b)}</for>
			<for {r in selections}>
				<div class="ui-code-selection" left={r.x} top={r.top} width={r.width} height={r.height} />
			</for>
			<for {r in matches}>
				<div class="ui-code-bracket" left={r.x} top={r.top} width={r.width} height={rowHeight} />
			</for>
			<for {i in slots}>{lineSlot(i, gutter, rowHeight)}</for>
			<div class="ui-code-gutter" left={Computed.make(() -> { revision.get(); (scroll == null ? 0 : scroll.x.get() : Single); })} width={Computed.make(() -> (gutter.get() : Single))} height={contentHeight}>
				<for {i in slots}>{gutterSlot(i, gutter, rowHeight)}</for>
			</div>
			<div class="ui-code-caret" left={Computed.make(() -> (gutter.get() + PAD + caret.get().x : Single))}
				top={Computed.make(() -> (PAD + caret.get().line * metrics.lineHeight : Single))} height={rowHeight}
				opacity={Computed.make(() -> (e.showsCaret() && !readOnly.get() && (scroll == null || caret.get().x >= scroll.x.get()) ? e.caretAlpha.get() : 0 : Single))} />
		</div>;
		pane = Library.part("ui-code-viewport", null, null, [content]);
		scroll = Scroll.attach(pane.node, true, true);
		var savedX = state.scrollX, savedY = state.scrollY;
		var restoringScroll = savedX != 0 || savedY != 0;
		state.attach(stateToken, () -> {
			state.caret = e.caret.get(); state.anchor = e.anchor.get();
			state.scrollX = restoringScroll ? savedX : scroll.x.get();
			state.scrollY = restoringScroll ? savedY : scroll.y.get();
		});
		refresh();
		var strip:Array<Element> = [pane];
		if (props.minimap == true)
			strip.push(CodeMinimap.make({
				document: document, metrics: metrics, scroll: scroll, viewHeight: viewHeight, viewWidth: viewWidth, boxWidth: boxWidth, revision: revision, tabSize: tabSize,
				pad: PAD, maxWidth: props.minimapWidth == null ? 96 : props.minimapWidth
			}));
		var data:Map<String, IntoReactive<Null<String>>> = ["mode" => editable() ? "editor" : "view"];
		if (props.minimap == true)
			data.set("minimap", "on");
		var box = Library.part("ui-code", null, data, strip.concat([search.view(Computed.make(() -> (Math.max(0, boxWidth.get()-16):Single)))]), props.id);
		var identity = Identity.of(pane.tree, pane.node.id);
		identity.setAttribute("role", "textbox").setAttribute("aria-multiline", "true").setAttribute("aria-label", props.label == null ? "Code" : props.label);
		new Watch(() -> readOnly.get(), on -> identity.setAttribute("aria-readonly", on ? "true" : "false"));
		var i = e.interaction = Interaction.of(pane.node).setFocusable(true);
		if (props.disabled != null) i.setDisabled(props.disabled);
		hints = new CodeHints({
			tree: pane.tree, rectAt: rectAt, offsetAt: offsetAt, provide: props.hover, decorationsAt: offset -> annotations.decorationsAt(offset),
			highlighter: name -> name == null ? syntax() : CodeSyntax.forLanguage(name), delay: props.hintDelay == null ? 0.45 : props.hintDelay
		});
		gutterNow = () -> gutter.get();
		Owner.onCleanup(hints.dispose);
		completions = new CodeCompletions({tree: pane.tree, rectAt: rectAt, text: () -> value.get(), caret: () -> e.caret.get(), apply: edits -> { applyEdits(edits); focus(); }});
		Owner.onCleanup(completions.hide);
		// The list narrows to what is typed, and goes when the caret leaves the word; the view moving takes its place.
		new Watch(() -> { revision.get(); e.caret.get(); e.anchor.get(); 0; }, _ -> completions.moved(), (_, _) -> false);
		new Watch(() -> { scroll.x.get(); scroll.y.get(); 0; }, _ -> completions.hide(), (_, _) -> false);
		// What the popover is beside is no longer there once the text or the view moves.
		new Watch(() -> { revision.get(); scroll.x.get(); scroll.y.get(); 0; }, _ -> hints.moved(), (_, _) -> false);
		i.onPointerDown(p -> {
			hints.hide();
			completions.hide();
			if (p.button != Left) return;
			if (props.onNavigate != null && (Sys.systemName() == "Mac" ? p.superKey : p.control)) {
				var offset = offsetAt(p.x, p.y);
				if (offset >= 0) {
					p.preventDefault();
					p.stopPropagation();
					props.onNavigate(offset);
					return;
				}
			}
			phase.send(Press);
			var at = point(p.x, p.y, gutter.get());
			e.press(at.x, at.y, p.shift, p.clickCount);
		});
		i.onPointerMove(p -> if (phase.state.get() == Selecting) {
			var at = point(p.x, p.y, gutter.get()); e.drag(at.x, at.y);
		} else
			hints.pointerAt(p.x, p.y));
		i.onPointerLeave(_ -> hints.pointerLeft());
		i.onPointerUp(_ -> phase.send(Release));
		i.onKeyDown(e.key); i.onKeyUp(e.keyUp); i.onTextInput(e.type); i.onComposition(e.compose);
		i.onFocus(_ -> { e.focus(); if (!editable() || e.readOnly) e.stopBlink(); });
		i.onBlur(_ -> { phase.send(Blur); e.blur(); e.stopBlink(); if (!hints.pointerOver()) hints.hide(); if (!completions.pointerOver()) completions.hide(); });
		e.onEscape = () -> if (hints.isOpen()) hints.hide() else Focus.clear(pane.tree);
		e.pageLines = () -> Std.int(Math.max(1, Math.floor(viewHeight.get() / metrics.lineHeight) - 1));
			var live = true, editorTree = pane.tree, probeIdentity = Identity.of(probe.tree, probe.node.id);
			var layout:LayoutTree->Bool = tree -> {
				if (!live || tree != editorTree) return false;
			// CSS has now committed the text face to native nodes. Measuring in
			// the restyle callback would cache positions for the previous font.
			var changed = false;
			if (fontDirty) {
				fontDirty = false; fontRevision++; metrics.invalidate(); metrics.prepare(e.display()); refresh(); changed = true;
			}
			var bounds = tree.getBounds(pane.node);
			// A retained, inactive tab has no layout box. Keep its last usable
			// viewport, so hiding it does not discard and recreate its rows (2aca664).
			if (bounds == null || bounds.width <= 0 || bounds.height <= 0) return changed;
			if (viewHeight.get() != bounds.height) { viewHeight.set(bounds.height); changed = true; }
			if (viewWidth.get() != bounds.width) { viewWidth.set(bounds.width); changed = true; }
			if (restoringScroll) {
				restoringScroll = false;
				scroll.jumpTo(savedX, savedY); changed = true;
			}
			// Folds and source replacement can leave the previous offset past the new content.
			var x = Math.min(scroll.x.get(), Math.max(0, contentWidth.get() - bounds.width));
			var y = Math.min(scroll.y.get(), Math.max(0, contentHeight.get() - bounds.height));
			if (x != scroll.x.get() || y != scroll.y.get()) { scroll.jumpTo(x, y); changed = true; }
			var outer = tree.getBounds(box.node);
			if (outer != null && outer.width > 0 && boxWidth.get() != outer.width) { boxWidth.set(outer.width); changed = true; }
			return changed;
		};
		LayoutTree.layoutHooks.push(layout);
			var restyle:Identity->Void = id -> if (live && id == probeIdentity) {
			var font = [for (field in ["font-size", "font-family", "font-weight", "font-style", "line-height", "letter-spacing"]) Css.resolved(id, field)].join("|");
			if (font != lastFont) { lastFont = font; fontDirty = true; }
		};
		Css.restyled.push(restyle);
		Owner.onCleanup(() -> {
				live = false;
				state.detach(stateToken);
				// Compare callback environments too: editor and viewer closures share
				// a function body, and generic Array.remove can remove the other one (3e75041).
				for (index in 0...LayoutTree.layoutHooks.length) if (Reflect.compareMethods(LayoutTree.layoutHooks[index], layout)) { LayoutTree.layoutHooks.splice(index, 1); break; }
				for (index in 0...Css.restyled.length) if (Reflect.compareMethods(Css.restyled[index], restyle)) { Css.restyled.splice(index, 1); break; }
			e.stopBlink(); metrics.invalidate(); cachedRows = [];
		});
		new Watch(() -> { revision.get(); e.caret.get(); e.anchor.get(); caret.get(); 0; }, _ -> reveal(gutter.get()), (_, _) -> false);
		new Watch(() -> e.showsCaret() && !readOnly.get(), on -> on ? e.restartBlink() : e.stopBlink());
		TextCaret.publish(e, () -> {
			if (readOnly.get()) return null;
			var b = pane.tree.getBounds(pane.node), stop = caret.get();
			return b == null ? null : {x: b.x + gutter.get() + PAD + stop.x - scroll.x.get(), y: b.y + PAD + stop.line * metrics.lineHeight - scroll.y.get(), width: 1.5, height: metrics.lineHeight};
		});
		return box;
	}

	/** Replaces `owner`'s decorations with `list`; an empty list clears them. With `follow`, they move with the text as it is edited. **/
	public function decorate(owner:String, list:Array<CodeDecoration>, follow = false):Void
		annotations.decorate(owner, list, follow);

	/** Replaces `owner`'s gutter markers with `list`, which leaves out a line the document does not have; needs `gutterMarkers`. With `follow`, they stay with their lines as the text is edited. **/
	public function markers(owner:String, list:Array<CodeMarker>, follow = false):Void
		annotations.mark(owner, list, follow);

	/** `owner`'s decorations as they are now, moved by the edits if it follows them. **/
	public function decorationsOf(owner:String):Array<CodeDecoration>
		return annotations.decorationsOf(owner);

	/** The lines `owner`'s markers are on now, moved by the edits if it follows them. **/
	public function markerLinesOf(owner:String):Array<Int>
		return annotations.markerLinesOf(owner);

	/** Where the character at `offset` is, in the window's coordinates; null when it is out of the view. **/
	public function rectAt(offset:Int):Null<CodeRect> {
		var b = pane == null ? null : pane.tree.getScrolledBounds(pane.node);
		if (b == null)
			return null;
		var text = editing.display(), at = Std.int(Math.max(0, Math.min(offset, text.length))), stop = editing.stopAt(at, text);
		var top = b.y + PAD + stop.line * metrics.lineHeight - scroll.y.get();
		if (top + metrics.lineHeight <= b.y || top >= b.y + b.height)
			return null;
		var next = at < text.length && text.charAt(at) != "\n" ? editing.stopAt(at + 1, text) : stop;
		return {x: b.x + gutterNow() + PAD + stop.x - scroll.x.get(), y: top, width: next.line == stop.line && next.x > stop.x ? next.x - stop.x : metrics.characterWidth, height: metrics.lineHeight};
	}

	/** The offset of the character under the point `(x, y)` in the window; -1 over the gutter, below the text or past the end of a line. **/
	public function offsetAt(x:Float, y:Float):Int {
		var b = pane == null ? null : pane.tree.getScrolledBounds(pane.node);
		if (b == null || x < b.x + gutterNow() || x >= b.x + b.width || y < b.y || y >= b.y + b.height)
			return -1;
		var px = x - b.x + scroll.x.get() - gutterNow() - PAD, row = editing.lineAtY(y - b.y + scroll.y.get() - PAD);
		if (row < 0 || row >= document.visible.length || px > editing.lineWidth(row))
			return -1;
		return editing.indexAt(Math.max(0, px - metrics.characterWidth / 2), row);
	}

	/** Opens `hint` in a popover at its range. `pinned`, it stays until `hideHint`, Escape, an edit or a scroll; otherwise it closes when the pointer leaves the range and the popover. **/
	public function showHint(hint:CodeHint, pinned = false):Void
		if (hints != null)
			hints.show(hint, pinned);

	public function hideHint():Void
		if (hints != null)
			hints.hide();

	/** The offset of the character the pointer rests on, or -1; for an app that answers `hover` later and opens the popover with `showHint`. **/
	public var hoverOffset(get, never):Int;

	function get_hoverOffset():Int
		return hints == null ? -1 : hints.hovered;

	/**
		Opens a list of `items` under the word that starts at `from` (the word before the caret by default), narrowed to what has
		been typed since; Up, Down, Enter, Tab and Escape work it, and the chosen one is put in the text as one undo step.
	**/
	public function showCompletions(items:Array<CodeCompletion>, ?from:Int):Void {
		if (completions == null)
			return;
		var text = value.get(), start = from == null ? editing.caret.get() : from;
		if (from == null)
			while (start > 0 && isWordCharacter(text.charCodeAt(start - 1)))
				start--;
		completions.show(items, start);
	}

	public function hideCompletions():Void
		if (completions != null)
			completions.hide();

	/** Whether the completion list is open. **/
	public function completionsOpen():Bool
		return completions != null && completions.isOpen();

	static function isWordCharacter(code:Int):Bool
		return code == "_".code || code == "$".code || (code >= "0".code && code <= "9".code) || (code >= "a".code && code <= "z".code) || (code >= "A".code && code <= "Z".code) || code > 127;

	/** The decorations over the character at `offset`, for a hover's `title`. **/
	public function decorationsAt(offset:Int):Array<CodeDecoration>
		return annotations.decorationsAt(offset);

	static function read<T>(value:IntoReactive<T>):T return switch value { case Const(v): v; case Bound(s): s.get(); case Derived(c): c.get(); }
	function refresh():Void revision.set(revision.get() + 1);

	/** The signal of slot `i`'s row, made with the slot. **/
	function slotAt(i:Int):Signal<Null<Row>> {
		while (slotRows.length <= i) {
			slotRows.push(Signal.make((null : Null<Row>)));
			slotTokens.push(Signal.make(([] : Array<Token>)));
			shownRows.push(null);
			slotPools.push(new Map());
			slotKinds.push([]);
		}
		return slotRows[i];
	}

	/** Gives each slot the row of the window it shows, setting only the slots whose row is another one. **/
	function distribute(list:Array<Row>, capacity:Int):Void {
		var next:Array<Null<Row>> = [for (_ in 0...capacity) null];
		for (row in list)
			if (row.row >= 0) next[row.row % capacity] = row;
		for (i in 0...Std.int(Math.max(capacity, shownRows.length))) {
			var row = i < capacity ? next[i] : null;
			if (i >= shownRows.length && row == null) continue;
			slotAt(i);
			if (shownRows[i] == row) continue;
			shownRows[i] = row;
			slotRows[i].set(row);
			fitTokens(i, row);
		}
	}

	/** Gives slot `i` the token elements of each kind that `row` needs: it keeps what it has, grows when a row has more, and gives back when a row needs under a quarter. **/
	function fitTokens(i:Int, row:Null<Row>):Void {
		var pools = slotPools[i], kinds = slotKinds[i], need = row == null ? null : row.byKind, changed = false;
		if (need != null)
			for (kind in need.keys())
				if (!pools.exists(kind)) {
					pools.set(kind, []);
					kinds.push(kind);
				}
		for (kind in kinds) {
			var pool = pools.get(kind), have = pool.length;
			var n = need == null || !need.exists(kind) ? 0 : need.get(kind).length;
			var room = n > have ? n : n * 4 < have && have > 16 ? Std.int(Math.max(n, 8)) : have;
			while (pool.length < room) {
				pool.push({kind: kind, index: pool.length});
				changed = true;
			}
			while (pool.length > room) {
				pool.pop();
				changed = true;
			}
		}
		if (changed)
			slotTokens[i].set([for (kind in kinds) for (token in pools.get(kind)) token]);
	}

	// A slot with no row is hidden, not faded to nothing: a group at no opacity is still drawn, into a layer of the window's size.
	function lineSlot(i:Int, gutter:Computed<Float>, rowHeight:Computed<Single>):Element {
		var row = slotAt(i);
		var shown = Computed.make(() -> (row.get() != null ? ashui.types.Style.Visibility.Visible : ashui.types.Style.Visibility.Hidden : ashui.types.Style.Visibility));
		var top = Computed.make(() -> { var r = row.get(); (r == null ? 0 : r.top : Single); });
		var width = Computed.make(() -> { var r = row.get(); (r == null ? 0 : r.width : Single); });
		var hintLeft = Computed.make(() -> { var r = row.get(); (r == null ? 0 : r.width + 8 : Single); });
		var guides = Computed.make(() -> { var r = row.get(); r == null ? [] : r.guides; });
		var tokens = Computed.make(() -> slotTokens[i].get());
		var folded = Computed.make(() -> { revision.get(); var r = row.get(); r != null && r.line.folded; });
		return <div class="ui-code-line" left={Computed.make(() -> (gutter.get() + PAD : Single))} top={top} height={rowHeight} width={width} visibility={shown}>
			<for {x in guides}><div class="ui-code-guide" left={x} height={rowHeight} /></for>
			<for {t in tokens}>{tokenSlot(row, t)}</for>
			<if {folded.get()}><text class="ui-code-text ui-code-fold-hint" left={hintLeft}> … </text></if>
		</div>;
	}

	function tokenSlot(row:Signal<Null<Row>>, token:Token):Element {
		function run(r:Null<Row>):Null<Run> {
			var list = r == null ? null : r.byKind.get(token.kind);
			return list != null && token.index < list.length ? list[token.index] : null;
		}
		var left = Computed.make(() -> { var u = run(row.get()); (u == null ? 0 : u.x : Single); });
		var content = Computed.make(() -> { var u = run(row.get()); u == null ? "" : u.text; });
		var text:Text = <text class="ui-code-text ui-code-token" left={left} top={0}>${content.get()}</text>;
		Identity.of(text.tree, text.node.id).setAttribute("data-token", token.kind);
		return text;
	}

	function gutterSlot(i:Int, gutter:Computed<Float>, rowHeight:Computed<Single>):Element {
		var row = slotAt(i);
		var shown = Computed.make(() -> (row.get() != null ? ashui.types.Style.Visibility.Visible : ashui.types.Style.Visibility.Hidden : ashui.types.Style.Visibility));
		var top = Computed.make(() -> { var r = row.get(); (r == null ? 0 : r.top : Single); });
		var number = Computed.make(() -> { var r = row.get(); r == null ? "" : Std.string(r.source + 1); });
		var foldable = Computed.make(() -> { revision.get(); var r = row.get(); r != null && r.line.foldEnd >= 0; });
		var fold = Computed.make(() -> (foldable.get() ? ashui.types.Style.Visibility.Visible : ashui.types.Style.Visibility.Hidden : ashui.types.Style.Visibility));
		return <div class="ui-code-gutter-line" top={top} height={rowHeight} width={Computed.make(() -> (gutter.get() : Single))} visibility={shown}>
			<if {props.gutterMarkers == true}>${markerSlot(row)}</if>
			<if {props.lineNumbers != false}><text class="ui-code-text ui-code-line-number" width={Computed.make(() -> (gutter.get() - (props.folding == false ? 8 : 26) - (props.gutterMarkers == true ? MARKER : 0) : Single))}>${number.get()}</text></if>
			<if {props.folding != false}>
				<div class="ui-code-fold-slot" visibility={fold}>${foldButton(row, foldable)}</div>
			</if>
		</div>;
	}

	function decorationMark(box:DecorationBox):Element {
		var mark = new Div({classes: ["ui-code-decoration", box.className], left: box.x, top: box.top, width: box.width, height: box.height});
		if (box.className.indexOf("ui-code-squiggle") >= 0)
			mark.appendChild(squiggle(waves(box.width)));
		return mark;
	}

	/** The waves widths come in, a few steps of a half more each, so any underline's wavy line is one of a few documents and atlas entries. **/
	static final WAVES = [4, 6, 8, 12, 16, 24, 32, 48, 64, 96, 128, 192, 256, 384, 512];

	/** The least of `WAVES` that covers `width`; the widest for any more. **/
	static function waves(width:Float):Int {
		var need = Math.ceil(width / SQUIGGLE);
		for (w in WAVES)
			if (w >= need)
				return w;
		return WAVES[WAVES.length - 1];
	}

	/** A wavy line `periods` waves wide, in the mark's text colour; the mark clips it to its own width, so the few widths there are share their documents. **/
	function squiggle(periods:Int):Svg {
		var width = periods * SQUIGGLE, path = new StringBuf();
		path.add("M0 3");
		for (i in 0...periods)
			path.add(' L${i * SQUIGGLE + SQUIGGLE / 2} 1 L${(i + 1) * SQUIGGLE} 3');
		return new Svg(SvgDocument.parse('<svg xmlns="http://www.w3.org/2000/svg" width="$width" height="4" viewBox="0 0 $width 4"><path d="${path.toString()}" fill="none" stroke="currentColor" stroke-width="1.1" stroke-linecap="round" stroke-linejoin="round"/></svg>'));
	}

	/** The gutter's marker slot of the row in `row`'s slot: its marker's class and title, and a press in it is the app's, never the editor's. **/
	function markerSlot(row:Signal<Null<Row>>):Element {
		var marker = Computed.make(() -> { revision.get(); annotations.revision.get(); var r = row.get(); r == null ? null : annotations.markerAt(r.source); });
		var classes = Computed.make(() -> { var m = marker.get(); m == null ? ["ui-code-marker"] : ["ui-code-marker", m.className]; });
		var dot = new Div({classes: classes});
		Identity.of(dot.tree, dot.node.id).bindAttribute("title", Computed.make(() -> { var m = marker.get(); (m == null ? null : m.title : Null<String>); }));
		var slot = Library.part("ui-code-marker-slot", null, null, [dot]);
		Interaction.of(slot.node).onPointerDown(p -> {
			var r = row.get();
			if (r == null) return;
			p.stopPropagation();
			if (onGutterClick != null) onGutterClick(r.source, p);
		});
		return slot;
	}

	// The button is always there and answers only while its slot's row opens a fold, so a row entering the window builds no button.
	function foldButton(slot:Signal<Null<Row>>, foldable:Computed<Bool>):Element {
		var folded = Computed.make(() -> { revision.get(); var r = slot.get(); r != null && r.line.folded; });
		var button:Div = <div class="ui-code-fold">
			<if {folded.get()}>
				<svg width={12} height={12} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m9 5 7 7-7 7" /></svg>
			<else>
				<svg width={12} height={12} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m5 9 7 7 7-7" /></svg>
			</if>
		</div>;
		// A plain element, not a Button: the gutter has one for each row slot, and a Button's styling is most of what one costs.
		Interaction.of(button.node).setFocusable(true).setDisabled(Computed.make(() -> !foldable.get()))
			.onPointerDown(event -> if (foldable.get()) event.stopPropagation())
			.onKeyDown(event -> if (foldable.get()) event.stopPropagation())
			.onClick(event -> { var r = slot.get(); if (r != null && r.line.foldEnd >= 0) { event.stopPropagation(); toggleFold(r.source); } });
		Identity.of(button.tree, button.node.id)
			.setAttribute("role", "button")
			.bindAttribute("aria-label", Computed.make(() -> { var r = slot.get(); (r == null ? null : (folded.get() ? "Expand" : "Fold") + " line " + (r.source + 1) : Null<String>); }))
			.bindAttribute("aria-expanded", Computed.make(() -> (folded.get() ? "false" : "true" : Null<String>)));
		return button;
	}

	// The rows from `windowStart` to `windowEnd` are built, three more than the view shows on each side. Until the probe's CSS font
	// is in, there are none: shaping and mounting them in the default proportional face would only be discarded (0973e0c).
	function windowStart():Int {
		revision.get();
		if (fontDirty) return 0;
		var y = scroll == null ? 0 : scroll.y.get();
		return Std.int(Math.max(0, Math.floor((y - PAD) / metrics.lineHeight) - 3));
	}

	function windowEnd():Int {
		revision.get();
		if (fontDirty) return 0;
		var y = scroll == null ? 0 : scroll.y.get();
		return Std.int(Math.min(document.visible.length, Math.ceil((y + viewHeight.get()) / metrics.lineHeight) + 3));
	}

	function visibleRows(first:Int, end:Int):Array<Row> {
		revision.get();
		if (fontDirty) return [];
		var stamp = fontRevision, lh = metrics.lineHeight;
		var result:Array<Row> = [];
		for (row in first...end) {
			var source = document.visible[row], line = document.lines[source], found:Null<Row> = null;
			for (old in cachedRows) if (old.line == line && old.source == source && old.row == row && old.stamp == stamp && old.tokens == line.tokenRevision) { found = old; break; }
			if (found == null) {
				var measured = metrics.measure(line), runs:Array<Run> = [];
				if (line.tokenCount == 0) runs.push({text: measured.expanded, x: 0, kind: "plain"});
				else for (t in 0...line.tokenCount) {
					var from = line.tokenFrom(t), to = line.tokenTo(t);
					runs.push({text: measured.expanded.substring(measured.columns[from], measured.columns[to]), x: (metrics.xAt(line, from) : Single), kind: line.tokenKind(t)});
				}
				var guides:Array<Single> = [];
				if (props.indentGuides == true) {
					var indent = 0;
					while (indent < measured.expanded.length && measured.expanded.charAt(indent) == " ") indent++;
					var column = tabSize;
					while (column <= indent) { guides.push((column * metrics.characterWidth : Single)); column += tabSize; }
				}
				var byKind = new Map<String, Array<Run>>();
				for (run in runs) {
					var list = byKind.get(run.kind);
					if (list == null) byKind.set(run.kind, list = []);
					list.push(run);
				}
				found = {line: line, source: source, row: row, top: (PAD + row * lh : Single), width: (measured.width : Single), runs: runs, byKind: byKind, guides: guides, stamp: stamp, tokens: line.tokenRevision};
			}
			result.push(found);
		}
		cachedRows = result;
		return result;
	}

	function point(x:Float, y:Float, gutter:Float):{x:Float, y:Float} {
		var b = pane.tree.getBounds(pane.node);
		return b == null ? {x: 0, y: 0} : {x: x - b.x + scroll.x.get() - gutter - PAD, y: y - b.y + scroll.y.get() - PAD};
	}

	function reveal(gutter:Float, force = false):Void {
		if (scroll == null || (!force && !editing.focused.get())) return;
		var at = editing.stopAt(editing.displayCaret(), editing.display()), lh = metrics.lineHeight;
		var x = scroll.x.get(), y = scroll.y.get(), top = PAD + at.line * lh, left = PAD + at.x;
		var height = viewHeight.get(), width = Math.max(1, viewWidth.get() - gutter);
		if (top < y + PAD) y = top - PAD;
		else if (top + lh + PAD > y + height) y = top + lh + PAD - height;
		if (left < x + PAD) x = left - PAD;
		else if (left + PAD > x + width) x = left + PAD - width;
		if (x != scroll.x.get() || y != scroll.y.get()) scroll.jumpTo(Math.max(0, x), Math.max(0, y));
	}

	/** Zero-based source line. Folding never changes the source or undo history. **/
	public function toggleFold(line:Int):Void {
		if (props.folding == false || !document.toggleFold(line)) return;
		var block = document.lines[line], end = document.lines[block.foldEnd];
		if (block.folded && ((editing.caret.get() > block.start + block.text.length && editing.caret.get() <= end.start + end.text.length)
			|| (editing.anchor.get() > block.start + block.text.length && editing.anchor.get() <= end.start + end.text.length))) {
			editing.caret.set(block.start + block.text.length); editing.anchor.set(editing.caret.get());
		}
		metrics.prepare(document.text); refresh();
	}
	public function expandAll():Void {
		for (line in document.lines) line.folded = false;
		document.mapRows(); metrics.prepare(document.text); refresh();
	}
	public function select(anchor:Int, caret:Int):Void {
		anchor = Std.int(Math.max(0, Math.min(value.get().length, anchor)));
		caret = Std.int(Math.max(0, Math.min(value.get().length, caret)));
		metrics.prepare(value.get());
		document.unfoldAt(anchor); document.unfoldAt(caret); refresh();
		editing.anchor.set(anchor); editing.caret.set(caret);
	}
	/** Scrolls the selected result into view without moving keyboard focus from a search field. **/
	public function revealSelection():Void reveal(gutterNow(), true);
	public function showFind(replace = false):Void search.show(replace);
	public function hideFind():Void search.hide();
	public function findNext(backward = false):Void search.next(backward);
	public function focus():Void Focus.set(editing.interaction, true);
	public function undo():Void restore(false);
	public function redo():Void restore(true);
	/**
		Replaces each stretch `from` to `to` of the text by its `text`, all as one undo step: a rename, or what a formatter answers with.
		The edits may come in any order, but must not overlap. The caret and the selection's anchor move with the text, to the end of
		what replaces them when they were inside a stretch. It applies where the user could not type, in a read-only editor too.
	**/
	public function applyEdits(edits:Array<CodeEdit>):Void {
		var old = value.get();
		function clamp(offset:Int):Int
			return Std.int(Math.max(0, Math.min(old.length, offset)));
		var sorted = edits.copy();
		sorted.sort((a, b) -> a.from != b.from ? a.from - b.from : a.to - b.to);
		var parts:Array<CodePatch> = [], text = new StringBuf(), at = 0;
		for (edit in sorted) {
			var from = clamp(edit.from), to = Std.int(Math.max(from, clamp(edit.to)));
			if (from < at)
				throw "code edits overlap";
			if (from == to && edit.text == "")
				continue;
			text.add(old.substring(at, from));
			text.add(edit.text);
			parts.push({from: from, removed: old.substring(from, to), inserted: edit.text});
			at = to;
		}
		if (parts.length == 0)
			return;
		text.add(old.substr(at));
		var next = text.toString();
		function moved(offset:Int):Int {
			var shift = 0;
			for (part in parts) {
				var end = part.from + part.removed.length;
				if (offset <= part.from)
					break;
				if (offset < end)
					return part.from + shift + part.inserted.length;
				shift += part.inserted.length - part.removed.length;
			}
			return offset + shift;
		}
		var before:CodeSelection = {caret: editing.caret.get(), anchor: editing.anchor.get()}, after:CodeSelection = {caret: moved(before.caret), anchor: moved(before.anchor)};
		history.recordParts(parts, before, after);
		oldText = "";
		knownValue = next;
		value.set(next);
		select(after.anchor, after.caret);
		if (props.onInput != null) props.onInput(next);
	}
	function restore(redo:Bool):Void {
		if (editing.readOnly || editing.interaction.disabled.get()) return;
		if (knownValue != value.get()) { history.clear(); oldText = ""; knownValue = value.get(); return; }
		var result = history.apply(value.get(), redo);
		if (result == null) return;
		knownValue = result.text; value.set(result.text);
		select(result.selection.anchor, result.selection.caret);
		editing.restartBlink();
		if (props.onInput != null) props.onInput(result.text);
	}
	function codeKey(event:KeyEvent):Bool {
		if (props.findShortcuts != false && search.shortcut(event)) return true;
		if (editing.readOnly) return false;
		var command = event.superKey || event.control;
		switch event.key {
			case Character(c) if (command && c.toLowerCase() == "z"):
				event.preventDefault(); event.shift ? redo() : undo(); return true;
			case Character(c) if (command && c.toLowerCase() == "y"):
				event.preventDefault(); redo(); return true;
			case Named(Tab):
				if (event.control || event.superKey || event.alt) return false;
				event.preventDefault(); indent(event.shift); return true;
			case Named(Enter) if (!command):
				event.preventDefault();
				var range = editing.selectionRange(), s = value.get(), start = s.lastIndexOf("\n", range.from - 1) + 1;
				if (range.from == 0) start = 0;
				var before = s.substring(start, range.from), count = 0;
				while (count < before.length && (before.charAt(count) == " " || before.charAt(count) == "\t")) count++;
				var pad = before.substr(0, count), trimmed = StringTools.rtrim(before);
				if (StringTools.endsWith(trimmed, "{") || StringTools.endsWith(trimmed, "[") || StringTools.endsWith(trimmed, ":")) pad += indentation();
				editing.replace("\n" + pad); return true;
			case _: return false;
		}
	}
	function indentation():String return props.insertSpaces == false ? "\t" : StringTools.lpad("", " ", tabSize);
	function indent(outdent:Bool):Void {
		var e = editing, s = value.get(), range = e.selectionRange();
		if (!outdent && range.from == range.to) {
			var lineStart = range.from == 0 ? 0 : s.lastIndexOf("\n", range.from - 1) + 1;
			var column = 0;
			for (i in lineStart...range.from) column += s.charAt(i) == "\t" ? tabSize - column % tabSize : 1;
			e.replace(props.insertSpaces == false ? "\t" : StringTools.lpad("", " ", tabSize - column % tabSize));
			return;
		}
		var from = range.from == 0 ? 0 : s.lastIndexOf("\n", range.from - 1) + 1;
		var to = s.indexOf("\n", range.to);
		if (to < 0) to = s.length;
		if (range.to > range.from && s.charAt(range.to - 1) == "\n") to = range.to - 1;
		var lines = s.substring(from, to).split("\n"), next:Array<String> = [];
		for (line in lines) {
			if (!outdent) next.push(indentation() + line);
			else {
				var count = 0;
				if (line.charAt(0) == "\t") count = 1;
				else while (count < tabSize && line.charAt(count) == " ") count++;
				next.push(line.substr(count));
			}
		}
		// Record both the original selection and the final indented selection.
		var selection:CodeSelection = {caret: e.caret.get(), anchor: e.anchor.get()};
		var beforeInput = e.onBeforeInput, input = e.onInput, replacement = next.join("\n");
		e.onBeforeInput = null; e.onInput = null;
		e.anchor.set(from); e.caret.set(to); e.replace(replacement);
		if (range.from == range.to) {
			var removed = lines[0].length - next[0].length;
			e.caret.set(Std.int(Math.max(from, range.from - removed))); e.anchor.set(e.caret.get());
		} else if (selection.caret < selection.anchor) {
			e.caret.set(from); e.anchor.set(from + replacement.length);
		} else { e.anchor.set(from); e.caret.set(from + replacement.length); }
		e.onBeforeInput = beforeInput; e.onInput = input;
		if (value.get() != s) {
			history.record(s, value.get(), selection, {caret: e.caret.get(), anchor: e.anchor.get()});
			knownValue = value.get();
			if (props.onInput != null) props.onInput(value.get());
		}
	}
}
