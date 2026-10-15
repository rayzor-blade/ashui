package ashui.components;

import ashui.components.code.CodeDocument;
import ashui.components.code.CodeDocument.CodeLine;
import ashui.components.code.CodeHighlighter;
import ashui.components.code.CodeHistory;
import ashui.components.code.CodeMetrics;
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
import ashui.ui.Div;
import ashui.ui.Text;
import ashui.ui.TextCaret;
import ashui.ui.TextEditing;

typedef CodeEditorProps = {
	/** A shared signal, initial string, or derived source. Line endings should be LF. **/
	?value:IntoReactive<String>,
	/** haxe, javascript/js, typescript/ts, rust, json, css, python/py, lua or plain. **/
	?language:IntoReactive<String>,
	/** An application grammar, in place of the built-in lexical highlighter. **/
	?highlighter:CodeHighlighter,
	?lineNumbers:Bool,
	?folding:Bool,
	?indentGuides:Bool,
	/** Spaces per tab stop and indentation level, 4 by default. **/
	?tabSize:Int,
	/** Insert spaces for Tab by default; false inserts a tab character. **/
	?insertSpaces:Bool,
	?readOnly:IntoReactive<Bool>,
	?disabled:IntoReactive<Bool>,
	?onInput:String->Void,
	?onSubmit:String->Void,
	/** Accessible name for the editing surface. **/
	?label:String,
	?id:String
}

private enum CodePhase { Resting; Selecting; }
private enum CodeEvent { Press; Release; Blur; }
private typedef Run = {text:String, kind:String, x:Single};
private typedef Row = {line:CodeLine, source:Int, row:Int, top:Single, runs:Array<Run>, width:Single, guides:Array<Single>, stamp:Int, tokens:Array<CodeToken>};

/**
	A virtualized code editor, built from Ashui text, buttons and scrolling
	(e53597f). The shared TextEditing engine handles grapheme navigation,
	clipboard, selection and IME. This view adds line highlighting, folding,
	indentation and bounded undo/redo. All appearance is components.css.
**/
class CodeEditor extends Component<CodeEditorProps> {
	public var value(default, null):Signal<String>;
	public var editing(default, null):TextEditing;
	public var document(default, null):CodeDocument;
	public var scroll(default, null):Scroll;
	public var metrics(default, null):CodeMetrics;
	final revision = Signal.make(0);
	final viewHeight = Signal.make(320.0);
	final viewWidth = Signal.make(600.0);
	final history = new CodeHistory();
	var pane:Div;
	var probe:Text;
	var cachedRows:Array<Row> = [];
	var oldText = "";
	var oldSelection:CodeSelection;
	var knownValue = "";
	var tabSize = 4;
	var lastFont = "";
	var fontRevision = 0;
	var fontDirty = true;
	var phase:Machine<CodePhase, CodeEvent>;
	static inline var PAD = 12.0;

	/** CodeView keeps the same selection and scrolling behavior without editing. **/
	function editable():Bool return true;

	function render():Element {
		Library.use();
		value = switch props.value {
			case null: Signal.make("");
			case Const(v): Signal.make(v);
			case Bound(s): s;
			case Derived(c): var s = Signal.make(c.get()); new Watch(() -> c.get(), v -> s.set(v)); s;
		}
		var language:IntoReactive<String> = props.language == null ? "plain" : props.language;
		var syntax = () -> props.highlighter != null ? props.highlighter : CodeSyntax.forLanguage(read(language));
		tabSize = Std.int(Math.max(1, Math.min(16, props.tabSize == null ? 4 : props.tabSize)));
		document = new CodeDocument(value.get(), syntax());
		metrics = new CodeMetrics(document, syntax(), tabSize);
		var e = editing = new TextEditing(value, true, 0);
		e.metrics = metrics;
		var shown = Computed.make(() -> e.display());
		probe = new Text("", {wrap: false});
		Identity.of(probe.tree, probe.node.id).addClasses(["ui-code-text", "ui-code-probe"]);
		metrics.text = probe;
		e.bindText(probe);
		knownValue = value.get();
		e.onBeforeInput = () -> { oldText = value.get(); oldSelection = {caret: e.caret.get(), anchor: e.anchor.get()}; };
		e.onInput = next -> {
			history.record(oldText, next, oldSelection, {caret: e.caret.get(), anchor: e.anchor.get()});
			oldText = "";
			knownValue = next;
			if (props.onInput != null) props.onInput(next);
		};
		e.onSubmit = props.onSubmit;
		e.onKey = codeKey;
		e.accept = s -> ~/\r\n|\r/g.replace(s, "\n");
		phase = new Machine<CodePhase, CodeEvent>(Resting, (state, event) -> switch [state, event] {
			case [_, Press]: Selecting;
			case [_, Release] | [_, Blur]: Resting;
		});
		phase.onExit(Selecting, _ -> e.release());
		var readOnly = Computed.make(() -> !editable() || (props.readOnly != null && read(props.readOnly)));
		new Watch(() -> readOnly.get(), on -> e.readOnly = on);
		new Watch(() -> { var content = shown.get(); var highlighter = syntax(); {content: content, highlighter: highlighter}; }, next -> {
			if (knownValue != value.get()) { history.clear(); oldText = ""; knownValue = value.get(); }
			metrics.syntax = next.highlighter;
			metrics.prepare(next.content);
			var length = value.get().length;
			if (e.caret.get() > length) e.caret.set(length);
			if (e.anchor.get() > length) e.anchor.set(length);
			refresh();
		}, (a, b) -> a.content == b.content && a.highlighter == b.highlighter);

		var rowHeight = Computed.make(() -> { revision.get(); (metrics.lineHeight : Single); });
		var gutter = Computed.make(() -> {
			revision.get();
			(props.lineNumbers == false ? 0 : Std.string(document.lines.length).length * metrics.characterWidth + 18)
				+ (props.folding == false ? 0 : 22) + (props.lineNumbers == false && props.folding == false ? 0 : 8);
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
		var rows = Computed.make(() -> visibleRows());
		var caret = Computed.make(() -> {
			revision.get(); e.fontSize.get();
			e.stopAt(e.displayCaret(), shown.get());
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
		var content = <div class="ui-code-content" width={contentWidth} height={contentHeight}>
			${probe}
			<div class="ui-code-active-line" top={Computed.make(() -> (PAD + caret.get().line * metrics.lineHeight : Single))}
				left={0} width={contentWidth} height={rowHeight} opacity={Computed.make(() -> (e.focused.get() ? 1 : 0 : Single))} />
			<for {r in selections}>
				<div class="ui-code-selection" left={r.x} top={r.top} width={r.width} height={r.height} />
			</for>
			<for {row in rows}>
				<div class="ui-code-line" left={Computed.make(() -> (gutter.get() + PAD : Single))} top={row.top} height={rowHeight} width={row.width}>
					<for {x in row.guides}><div class="ui-code-guide" left={x} height={rowHeight} /></for>
					<for {run in row.runs}>${token(run)}</for>
					<if {folded(row)}><text class="ui-code-text ui-code-fold-hint" left={row.width + 8}> … </text></if>
				</div>
			</for>
			<div class="ui-code-gutter" left={Computed.make(() -> { revision.get(); (scroll == null ? 0 : scroll.x.get() : Single); })} width={Computed.make(() -> (gutter.get() : Single))} height={contentHeight}>
				<for {row in rows}>
					<div class="ui-code-gutter-line" top={row.top} height={rowHeight} width={Computed.make(() -> (gutter.get() : Single))}>
						<if {props.lineNumbers != false}><text class="ui-code-text ui-code-line-number" width={Computed.make(() -> (gutter.get() - (props.folding == false ? 8 : 26) : Single))}>${Std.string(row.source + 1)}</text></if>
						<if {props.folding != false}>
							<div class="ui-code-fold-slot">
								<if {row.line.foldEnd >= 0}>${foldButton(row)}</if>
							</div>
						</if>
					</div>
				</for>
			</div>
			<div class="ui-code-caret" left={Computed.make(() -> (gutter.get() + PAD + caret.get().x : Single))}
				top={Computed.make(() -> (PAD + caret.get().line * metrics.lineHeight : Single))} height={rowHeight}
				opacity={Computed.make(() -> (e.showsCaret() && !readOnly.get() && (scroll == null || caret.get().x >= scroll.x.get()) ? e.caretAlpha.get() : 0 : Single))} />
		</div>;
		pane = Library.part("ui-code-viewport", null, null, [content]);
		scroll = Scroll.attach(pane.node, true, true);
		refresh();
		var box = Library.part("ui-code", null, ["mode" => editable() ? "editor" : "view"], [pane], props.id);
		var identity = Identity.of(pane.tree, pane.node.id);
		identity.setAttribute("role", "textbox").setAttribute("aria-multiline", "true").setAttribute("aria-label", props.label == null ? "Code" : props.label);
		new Watch(() -> readOnly.get(), on -> identity.setAttribute("aria-readonly", on ? "true" : "false"));
		var i = e.interaction = Interaction.of(pane.node).setFocusable(true);
		if (props.disabled != null) i.setDisabled(props.disabled);
		i.onPointerDown(p -> {
			if (p.button != Left) return;
			phase.send(Press);
			var at = point(p.x, p.y, gutter.get());
			e.press(at.x, at.y, p.shift, p.clickCount);
		});
		i.onPointerMove(p -> if (phase.state.get() == Selecting) {
			var at = point(p.x, p.y, gutter.get()); e.drag(at.x, at.y);
		});
		i.onPointerUp(_ -> phase.send(Release));
		i.onKeyDown(e.key); i.onKeyUp(e.keyUp); i.onTextInput(e.type); i.onComposition(e.compose);
		i.onFocus(_ -> { e.focus(); if (!editable() || e.readOnly) e.stopBlink(); });
		i.onBlur(_ -> { phase.send(Blur); e.blur(); e.stopBlink(); });
		e.onEscape = () -> Focus.clear(pane.tree);
		e.pageLines = () -> Std.int(Math.max(1, Math.floor(viewHeight.get() / metrics.lineHeight) - 1));
		var layout:LayoutTree->Bool = tree -> {
			if (tree != pane.tree) return false;
			// CSS has now committed the text face to native nodes. Measuring in
			// the restyle callback would cache positions for the previous font.
			var changed = false;
			if (fontDirty) {
				fontDirty = false; fontRevision++; metrics.invalidate(); metrics.prepare(shown.get()); refresh(); changed = true;
			}
			var bounds = tree.getBounds(pane.node);
			if (bounds == null) return changed;
			if (viewHeight.get() != bounds.height) { viewHeight.set(bounds.height); changed = true; }
			if (viewWidth.get() != bounds.width) { viewWidth.set(bounds.width); changed = true; }
			return changed;
		};
		LayoutTree.layoutHooks.push(layout);
		var restyle:Identity->Void = id -> if (id == Identity.of(probe.tree, probe.node.id)) {
			var font = [for (field in ["font-size", "font-family", "font-weight", "font-style", "line-height", "letter-spacing"]) Css.resolved(id, field)].join("|");
			if (font != lastFont) { lastFont = font; fontDirty = true; }
		};
		Css.restyled.push(restyle);
		Owner.onCleanup(() -> {
			LayoutTree.layoutHooks.remove(layout); Css.restyled.remove(restyle);
			e.stopBlink(); metrics.invalidate(); history.clear(); cachedRows = [];
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

	static function read<T>(value:IntoReactive<T>):T return switch value { case Const(v): v; case Bound(s): s.get(); case Derived(c): c.get(); }
	function refresh():Void revision.set(revision.get() + 1);
	function token(run:Run):Element {
		var text:Text = <text class="ui-code-text ui-code-token" left={run.x} top={0}>${run.text}</text>;
		Identity.of(text.tree, text.node.id).setAttribute("data-token", run.kind);
		return text;
	}
	function foldButton(row:Row):Element {
		var button:Button = <button type="button" variant={Ghost} size={Icon} class="ui-code-fold"
			onPointerDown={event -> event.stopPropagation()} onKeyDown={event -> event.stopPropagation()}
			onClick={event -> { event.stopPropagation(); toggleFold(row.source); }}>
			<if {folded(row)}>
				<svg width={12} height={12} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m9 5 7 7-7 7" /></svg>
			<else>
				<svg width={12} height={12} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m5 9 7 7 7-7" /></svg>
			</if>
		</button>;
		Identity.of(button.tree, button.node.id)
			.bindAttribute("aria-label", Computed.make(() -> ((folded(row) ? "Expand" : "Fold") + " line " + (row.source + 1) : Null<String>)))
			.bindAttribute("aria-expanded", Computed.make(() -> (folded(row) ? "false" : "true" : Null<String>)));
		return button;
	}
	function folded(row:Row):Bool { revision.get(); return row.line.folded; }

	function visibleRows():Array<Row> {
		revision.get();
		var stamp = fontRevision;
		var y = scroll == null ? 0 : scroll.y.get(), h = viewHeight.get(), lh = metrics.lineHeight;
		var first = Std.int(Math.max(0, Math.floor((y - PAD) / lh) - 3));
		var end = Std.int(Math.min(document.visible.length, Math.ceil((y + h) / lh) + 3));
		var result:Array<Row> = [];
		for (row in first...end) {
			var source = document.visible[row], line = document.lines[source], found:Null<Row> = null;
			for (old in cachedRows) if (old.line == line && old.source == source && old.row == row && old.stamp == stamp && old.tokens == line.tokens) { found = old; break; }
			if (found == null) {
				var measured = metrics.measure(line), runs:Array<Run> = [];
				if (line.tokens.length == 0) runs.push({text: measured.expanded, x: 0, kind: "plain"});
				else for (token in line.tokens) runs.push({text: measured.expanded.substring(measured.columns[token.from], measured.columns[token.to]), x: (metrics.xAt(line, token.from) : Single), kind: token.kind});
				var guides:Array<Single> = [];
				if (props.indentGuides == true) {
					var indent = 0;
					while (indent < measured.expanded.length && measured.expanded.charAt(indent) == " ") indent++;
					var column = tabSize;
					while (column <= indent) { guides.push((column * metrics.characterWidth : Single)); column += tabSize; }
				}
				found = {line: line, source: source, row: row, top: (PAD + row * lh : Single), width: (measured.width : Single), runs: runs, guides: guides, stamp: stamp, tokens: line.tokens};
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

	function reveal(gutter:Float):Void {
		if (scroll == null || !editing.focused.get()) return;
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
	public function focus():Void Focus.set(editing.interaction, true);
	public function undo():Void restore(false);
	public function redo():Void restore(true);
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
