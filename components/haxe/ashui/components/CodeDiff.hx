package ashui.components;

import ashui.components.code.CodeDiffText;
import ashui.components.code.CodeDiffPane;
import ashui.components.code.CodeDiffPane.CodeDiffAction;
import ashui.components.code.CodeDiffPane.CodeDiffFont;
import ashui.components.code.CodeDiffRows;
import ashui.components.code.CodeDiffer;
import ashui.components.code.CodeDiffer.CodeChange;
import ashui.components.code.CodeDocument;
import ashui.components.code.CodeHighlighter;
import ashui.components.code.CodeMetrics;
import ashui.components.code.CodeSyntax;
import ashui.css.Css;
import ashui.css.Identity;
import ashui.input.Interaction;
import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.layout.LayoutTree;
import ashui.reactive.Computed;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.reactive.Watch;
import ashui.ui.Component;
import ashui.ui.Div;
import ashui.ui.Text;

/** How the two texts are laid out: one column of removed and added lines, or the original and the modified text side by side. **/
enum abstract CodeDiffLayout(String) from String to String {
	var Inline = "inline";
	var Split = "split";
}

/** Icons the diff draws its own controls with, in place of the ones it has; each is an icon from a set, a compiled document or SVG markup that draws in `currentColor`. **/
typedef CodeDiffIconProps = {
	/** The button for the previous change, in the navigation bar. **/
	?previous:ashui.svg.Icon,
	/** The button for the next change. **/
	?next:ashui.svg.Icon,
	/** The mark at the start of the row of a folded run of unchanged lines. **/
	?folded:ashui.svg.Icon,
	/** The button of `onStage`. **/
	?stage:ashui.svg.Icon,
	/** The button of `onRevert`. **/
	?revert:ashui.svg.Icon
}

typedef CodeDiffProps = {
	/** The text before, as a string or a signal of one. Line endings should be LF. **/
	original:IntoReactive<String>,
	/** The text after. **/
	modified:IntoReactive<String>,
	/** haxe/hxx, javascript/js/jsx, typescript/ts/tsx, rust, json, css, python/py, lua or plain, as CodeEditor takes it. **/
	?language:IntoReactive<String>,
	/** An application grammar, in place of the built-in lexical highlighter. **/
	?highlighter:CodeHighlighter,
	/** `Inline` (the default) or `Split`; a signal switches between them. **/
	?layout:IntoReactive<CodeDiffLayout>,
	/**
		The changes, when the caller has them, as a version-control library gives them: take the runs of removed and added lines of
		a patch, not a hunk with its context lines. They are checked against the two texts, and ignored if they do not fit. Without
		them the component finds the changes itself.
	**/
	?hunks:IntoReactive<Array<CodeChange>>,
	/** Unchanged lines kept on each side of a change, 3 by default; the rest of a long run is a row that opens when pressed. A negative number keeps every line. **/
	?context:Int,
	/** Line numbers, true by default. **/
	?lineNumbers:Bool,
	/** A bar above the rows with "2 of 5" and buttons for the previous and the next change; off by default. F7 and Shift+F7 work with or without it. **/
	?navigation:Bool,
	/** Spaces per tab stop, 4 by default. **/
	?tabSize:Int,
	/** Called with a change when its Stage button is pressed. Setting it puts a Stage button, with a tooltip, on the first row of each change. **/
	?onStage:CodeChange->Void,
	/** Called with a change when its Revert button is pressed; likewise puts a Revert button on each. **/
	?onRevert:CodeChange->Void,
	/** More buttons on the first row of each change, after Stage and Revert: `{label, ?icon, run}`. **/
	?hunkActions:Array<CodeDiffAction>,
	/** Icons for the diff's own controls, in place of the plain ones it draws; give a set's, such as Remix's, to match an app. **/
	?icons:CodeDiffIconProps,
	/** Accessible name of the diff. **/
	?label:String,
	?id:String
}

/**
	Two versions of a text compared: the lines that were removed and added shown in colour, the words changed inside an edited line
	marked, the numbers of both texts in the gutter, and long runs of unchanged lines folded into a row that opens when pressed.
	Inline puts the removed and added lines in one column; side by side puts the original and the modified text in two columns that
	scroll together, a filler opposite each line the other side does not have. Rows are all one height and pooled as the code
	editor's are, so a file of tens of thousands of lines scrolls as smoothly as one editor.

	It is read-only. The comparison of a large pair of texts runs on the worker thread (`Worker`), and the previous rows stay until
	it is done.
**/
class CodeDiff extends Component<CodeDiffProps> {
	/** How many changes the texts have. **/
	public final changeCount = Signal.make(0);

	/** The change last gone to with `goToChange`, from 0; -1 before any. **/
	public final currentChange = Signal.make(-1);

	/** Whether a comparison is running on the worker thread. **/
	public final comparing = Signal.make(false);

	final rows = Signal.make((null : Null<CodeDiffRows>));
	final revision = Signal.make(0);
	final font = new CodeDiffFont();
	final opened = new Map<Int, Bool>();
	var allOpen = false;
	var compared:Null<{original:Array<String>, modified:Array<String>, changes:Array<CodeChange>}> = null;
	var version = 0;
	var panes:Array<CodeDiffPane> = [];
	var originalMetrics:CodeMetrics;
	var modifiedMetrics:CodeMetrics;
	var originalText:CodeDiffText;
	var modifiedText:CodeDiffText;
	var probe:Text;
	var tabSize = 4;
	var layoutNow:Void->CodeDiffLayout = () -> Inline;

	/** The icons the controls have unless the app gives others: plain strokes, so the component needs no icon set. **/
	static final PREVIOUS:ashui.svg.Icon = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M6 15 L12 9 L18 15"/></svg>';

	static final NEXT:ashui.svg.Icon = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M6 9 L12 15 L18 9"/></svg>';

	static final STAGE:ashui.svg.Icon = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 5 V19 M5 12 H19"/></svg>';

	static final REVERT:ashui.svg.Icon = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M9 14 L4 9 L9 4"/><path d="M4 9 H15 A5 5 0 0 1 15 19 H11"/></svg>';

	static final FOLDED:ashui.svg.Icon = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M8 9 L12 5 L16 9"/><path d="M8 15 L12 19 L16 15"/></svg>';

	/** Past this many lines in both texts together, the comparison runs on the worker thread. **/
	static inline var SYNCHRONOUS = 4000;

	/** A text of at least this many lines has its lexical checkpoints made ahead, `FILL_SLICE` lines a frame. **/
	static inline var FILLING = 5000;

	static inline var FILL_SLICE = 4000;

	var fills = 0;

	function render():Element {
		Library.use();
		var originalValue = source(props.original), modifiedValue = source(props.modified);
		var language:IntoReactive<String> = props.language == null ? "plain" : props.language;
		var syntax = () -> props.highlighter != null ? props.highlighter : CodeSyntax.forLanguage(read(language));
		tabSize = Std.int(Math.max(1, Math.min(16, props.tabSize == null ? 4 : props.tabSize)));
		layoutNow = () -> props.layout == null ? Inline : read(props.layout);
		probe = new Text("", {wrap: false});
		Identity.of(probe.tree, probe.node.id).addClasses(["ui-code-text", "ui-code-probe"]);
		originalMetrics = new CodeMetrics(new CodeDocument("", syntax()), syntax(), tabSize);
		modifiedMetrics = new CodeMetrics(new CodeDocument("", syntax()), syntax(), tabSize);
		originalMetrics.text = probe;
		modifiedMetrics.text = probe;
		originalText = new CodeDiffText(syntax());
		modifiedText = new CodeDiffText(syntax());

		function accept(a:Array<String>, b:Array<String>, changes:Array<CodeChange>):Void {
			// The texts' lines are kept as the comparison had them, and coloured as rows ask; no document is made of either.
			originalText.reset(a, syntax());
			modifiedText.reset(b, syntax());
			originalMetrics.prepare("");
			modifiedMetrics.prepare("");
			compared = {original: a, modified: b, changes: changes};
			fillCheckpoints(originalText, ++fills);
			fillCheckpoints(modifiedText, fills);
			opened.clear();
			allOpen = false;
			changeCount.set(changes.length);
			if (currentChange.get() >= changes.length)
				currentChange.set(-1);
			comparing.set(false);
			rebuild();
			revision.set(revision.get() + 1);
		}
		new Watch(() -> {
			var ta = originalValue.get(), tb = modifiedValue.get(), given = props.hunks == null ? null : read(props.hunks);
			{original: ta, modified: tb, hunks: given, language: read(language), highlighter: props.highlighter};
		}, next -> {
			var a = CodeDiffer.split(next.original), b = CodeDiffer.split(next.modified), given = next.hunks;
			if (given != null && CodeDiffer.valid(a, b, given))
				return accept(a, b, given);
			if (a.length + b.length <= SYNCHRONOUS)
				return accept(a, b, CodeDiffer.lines(a, b));
			var mine = ++version;
			comparing.set(true);
			ashui.core.Worker.run(() -> CodeDiffer.lines(a, b), found -> if (mine == version) accept(a, b, found));
		}, (a, b) -> a.original == b.original && a.modified == b.modified && a.hunks == b.hunks && a.language == b.language && a.highlighter == b.highlighter);
		new Watch(() -> layoutNow(), _ -> rebuild(), (a, b) -> a == b);

		var layouts = Computed.make(() -> [layoutNow()]);
		var parts:Array<Element> = [];
		if (props.navigation == true)
			parts.push(navigationBar());
		parts.push(<for {l in layouts}>{body(l)}</for>);
		parts.push(<if {comparing.get()}><text class="ui-code-text ui-code-diff-status">Comparing…</text></if>);
		var box = Library.part("ui-code-diff", null, ["layout" => Computed.make(() -> (layoutNow() : Null<String>))], parts, props.id);

		var live = true, editorTree = box.tree, probeIdentity = Identity.of(probe.tree, probe.node.id), lastFont = "";
		var layout:LayoutTree->Bool = tree -> {
			if (!live || tree != editorTree)
				return false;
			// CSS has now committed the text face to native nodes; measuring in the restyle callback would measure the previous font.
			var changed = false;
			if (font.dirty) {
				font.dirty = false;
				font.revision++;
				originalMetrics.invalidate();
				modifiedMetrics.invalidate();
				originalMetrics.prepare("");
				modifiedMetrics.prepare("");
				revision.set(revision.get() + 1);
				changed = true;
			}
			for (pane in panes)
				if (pane.measure(tree))
					changed = true;
			return changed;
		};
		LayoutTree.layoutHooks.push(layout);
		var restyle:Identity->Void = id -> if (live && id == probeIdentity) {
			var next = [for (field in ["font-size", "font-family", "font-weight", "font-style", "line-height", "letter-spacing"]) Css.resolved(id, field)].join("|");
			if (next != lastFont) {
				lastFont = next;
				font.dirty = true;
			}
		};
		Css.restyled.push(restyle);
		Owner.onCleanup(() -> {
			live = false;
			// Compare the callback environments too: other views share a function body, and generic Array.remove can remove theirs.
			for (index in 0...LayoutTree.layoutHooks.length)
				if (Reflect.compareMethods(LayoutTree.layoutHooks[index], layout)) {
					LayoutTree.layoutHooks.splice(index, 1);
					break;
				}
			for (index in 0...Css.restyled.length)
				if (Reflect.compareMethods(Css.restyled[index], restyle)) {
					Css.restyled.splice(index, 1);
					break;
				}
			originalMetrics.invalidate();
			modifiedMetrics.invalidate();
		});
		return box;
	}

	/** The panes of a layout: one for inline, two for side by side with their vertical scroll tied together. **/
	function body(layout:CodeDiffLayout):Element {
		var lineNumbers = props.lineNumbers != false, actions:Array<CodeDiffAction> = [];
		if (props.onStage != null)
			actions.push({label: "Stage change", icon: props.icons != null && props.icons.stage != null ? props.icons.stage : STAGE, run: props.onStage});
		if (props.onRevert != null)
			actions.push({label: "Revert change", icon: props.icons != null && props.icons.revert != null ? props.icons.revert : REVERT, run: props.onRevert});
		if (props.hunkActions != null)
			actions = actions.concat(props.hunkActions);
		function pane(side:CodeDiffSide, label:String, actions:Array<CodeDiffAction>):CodeDiffPane
			return new CodeDiffPane({
				side: side,
				rows: rows,
				original: originalMetrics,
				modified: modifiedMetrics,
				originalText: originalText,
				modifiedText: modifiedText,
				tabSize: tabSize,
				foldIcon: props.icons != null && props.icons.folded != null ? props.icons.folded : FOLDED,
				revision: revision,
				font: font,
				lineNumbers: lineNumbers,
				actions: actions,
				open: line -> {
					opened.set(line, true);
					rebuild();
				},
				step: delta -> goToChange(delta),
				label: label
			});
		var made:Array<CodeDiffPane>, children:Array<Element>;
		if (layout == Split) {
			var left = pane(Original, (props.label == null ? "Diff" : props.label) + ", original", []), right = pane(Modified, (props.label == null ? "Diff" : props.label) + ", modified", actions);
			// Their vertical scroll is one, so rows line up; each scrolls sideways on its own.
			new Watch(() -> left.scroll.y.get(), y -> if (right.scroll.y.get() != y) right.scroll.jumpTo(right.scroll.x.get(), y));
			new Watch(() -> right.scroll.y.get(), y -> if (left.scroll.y.get() != y) left.scroll.jumpTo(left.scroll.x.get(), y));
			made = [left, right];
			children = [left.view, new Div({classes: ["ui-code-diff-divider"]}), right.view];
		} else {
			var only = pane(Inline, props.label == null ? "Diff" : props.label, actions);
			made = [only];
			children = [only.view];
		}
		panes = panes.concat(made);
		Owner.onCleanup(() -> {
			for (p in made)
				panes.remove(p);
		});
		var row = new Div({classes: ["ui-code-diff-panes"]}, children);
		return row;
	}

	/** The bar of the `navigation` prop: where the view is among the changes, and buttons for the previous and the next. **/
	function navigationBar():Element {
		var text = Computed.make(() -> {
			var n = changeCount.get(), c = currentChange.get();
			n == 0 ? "No changes" : c < 0 ? (n == 1 ? "1 change" : n + " changes") : (c + 1) + " of " + n;
		});
		var none = Computed.make(() -> changeCount.get() == 0);
		var label = new Text(text, {wrap: false});
		Identity.of(label.tree, label.node.id).addClasses(["ui-code-diff-bar-text"]);
		function button(name:String, document:ashui.svg.Icon, delta:Int):Element {
			var glyph = new Icon({document: document});
			Identity.of(glyph.tree, glyph.node.id).addClasses(["ui-code-diff-nav-glyph"]);
			var nav = new Div({classes: ["ui-code-diff-nav"]}, [glyph]);
			Interaction.of(nav.node).setFocusable(true).setDisabled(none).onClick(_ -> goToChange(delta));
			Identity.of(nav.tree, nav.node.id).setAttribute("role", "button").setAttribute("aria-label", name);
			return new Tooltip({label: name, side: "bottom", delay: 0.3}, [nav]);
		}
		return Library.part("ui-code-diff-bar", null, null, [
			label,
			button("Previous change (Shift+F7)", props.icons != null && props.icons.previous != null ? props.icons.previous : PREVIOUS, -1),
			button("Next change (F7)", props.icons != null && props.icons.next != null ? props.icons.next : NEXT, 1)
		]);
	}

	/** Scrolls to the next change after the current one, or after where the view is when the current one is off screen; wraps from the last to the first. **/
	public function nextChange():Void
		goToChange(1);

	/** Scrolls to the previous change; wraps from the first to the last. **/
	public function previousChange():Void
		goToChange(-1);

	/** Scrolls to the change `index`, from 0, and makes it the current one. An index out of range is brought into it. **/
	public function showChange(index:Int):Void {
		var set = rows.get();
		if (set == null || set.changes.length == 0 || panes.length == 0)
			return;
		var target = Std.int(Math.max(0, Math.min(set.changes.length - 1, index)));
		currentChange.set(target);
		for (p in panes)
			p.scrollToRow(set.rowOfChange(target));
	}

	/** Scrolls to the change `delta` away from the current one, or from where the view is when the current one is off screen; wraps at both ends. **/
	public function goToChange(delta:Int):Void {
		var set = rows.get();
		if (set == null || set.changes.length == 0 || panes.length == 0)
			return;
		var n = set.changes.length, pane = panes[panes.length - 1], current = currentChange.get(), target:Int;
		if (current >= 0 && current < n && pane.rowVisible(set.rowOfChange(current)))
			target = ((current + delta) % n + n) % n;
		else {
			var top = pane.topRow();
			if (delta >= 0) {
				target = 0;
				for (c in 0...n)
					if (set.rowOfChange(c) > top) {
						target = c;
						break;
					}
			} else {
				target = n - 1;
				var c = n - 1;
				while (c >= 0) {
					if (set.rowOfChange(c) < top) {
						target = c;
						break;
					}
					c--;
				}
			}
		}
		showChange(target);
	}

	/** Scrolls to the line `line` of the modified text, from 0, opening the folded run that hides it. **/
	public function reveal(line:Int):Void {
		var set = rows.get(), c = compared;
		if (set == null || c == null || panes.length == 0)
			return;
		var row = set.rowOfModified(Std.int(Math.max(0, Math.min(c.modified.length - 1, line))));
		if (row < set.count && set.hiddenAt(row) > 0) {
			opened.set(set.modifiedAt(row), true);
			rebuild();
			set = rows.get();
			row = set.rowOfModified(line);
		}
		for (p in panes)
			if (!p.rowVisible(row))
				p.scrollToRow(row, true);
	}

	/** Opens every folded run of unchanged lines. **/
	public function expandAll():Void {
		allOpen = true;
		rebuild();
	}

	/** Folds the runs opened since the texts were last compared. **/
	public function collapseAll():Void {
		allOpen = false;
		opened.clear();
		rebuild();
	}

	/** Makes the lexical checkpoints of a large text a slice at a time between frames, so far jumps through it have little to work out. **/
	function fillCheckpoints(text:CodeDiffText, generation:Int):Void {
		if (text.length < FILLING)
			return;
		function slice():Void
			if (generation == fills && !text.fill(FILL_SLICE))
				ashui.animation.AnimationScheduler.main.after(0, slice);
		ashui.animation.AnimationScheduler.main.after(0, slice);
	}

	/** Makes the rows again from the texts compared, for the layout now, with the runs opened so far kept whole. **/
	function rebuild():Void {
		var c = compared;
		rows.set(c == null ? null : CodeDiffRows.build(c.original, c.modified, c.changes, layoutNow() == Split, props.context == null ? 3 : props.context,
			key -> allOpen || opened.exists(key)));
	}

	/** The changes now compared, as the rows were made from them. **/
	public function changes():Array<CodeChange>
		return compared == null ? [] : compared.changes;

	/** What the panes show now, row by row, in each pane's order; for checks. **/
	public function shownNow():Array<Array<{row:Int, kind:String, text:String, oldNumber:String, newNumber:String}>>
		return [for (p in panes) p.shownNow()];

	static function source(value:IntoReactive<String>):Signal<String>
		return switch value {
			case Const(v): Signal.make(v);
			case Bound(s): s;
			case Derived(c):
				var s = Signal.make(c.get());
				new Watch(() -> c.get(), v -> s.set(v));
				s;
		}

	static function read<T>(value:IntoReactive<T>):T
		return switch value {
			case Const(v): v;
			case Bound(s): s.get();
			case Derived(c): c.get();
		}
}
