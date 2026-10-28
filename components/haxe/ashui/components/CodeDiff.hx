package ashui.components;

import ashui.components.code.CodeDiffText;
import ashui.components.code.CodeDiffPane;
import ashui.components.code.CodeDiffPane.CodeDiffAction;
import ashui.components.code.CodeDiffPane.CodeDiffFont;
import ashui.components.code.CodeDiffRows;
import ashui.components.code.CodeDiffHint;
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

/** Diff arrangement: removed and added lines in one column, or original and modified text side by side. **/
enum abstract CodeDiffLayout(String) from String to String {
	var Inline = "inline";
	var Split = "split";
}

/** Replacement icons for diff controls. Accepts icon-set entries, compiled SVGs, or markup using `currentColor`. **/
typedef CodeDiffIconProps = {
	/** Previous-change navigation icon. **/
	?previous:ashui.svg.Icon,
	/** Next-change navigation icon. **/
	?next:ashui.svg.Icon,
	/** Icon for a collapsed section of unchanged lines. **/
	?folded:ashui.svg.Icon,
	/** Stage action icon. **/
	?stage:ashui.svg.Icon,
	/** Revert action icon. **/
	?revert:ashui.svg.Icon
}

typedef CodeDiffProps = {
	/** Original text. Accepts reactive values; use LF line endings. **/
	original:IntoReactive<String>,
	/** Modified text. Accepts reactive values; use LF line endings. **/
	modified:IntoReactive<String>,
	/** Syntax language, using the same names and aliases as `CodeEditor`. **/
	?language:IntoReactive<String>,
	/** Custom highlighter that replaces the built-in lexical highlighter. **/
	?highlighter:CodeHighlighter,
	/** `Inline` (default) or `Split`. Reactive changes switch the layout. **/
	?layout:IntoReactive<CodeDiffLayout>,
	/**
		Optional changes supplied by a version-control library. Supply runs of
		removed and added lines, excluding context lines. Changes are validated
		against both texts and ignored when they do not match. When omitted,
		the component computes the diff.
	**/
	?hunks:IntoReactive<Array<CodeChange>>,
	/** Unchanged context lines on each side of a change. Defaults to 3; negative keeps all lines. Longer unchanged runs collapse into expandable rows. **/
	?context:Int,
	/** Shows line numbers. Defaults to true. **/
	?lineNumbers:Bool,
	/** Shows a change counter and previous/next buttons. Defaults to false. F7 and Shift+F7 work regardless of this setting. **/
	?navigation:Bool,
	/** Spaces per tab stop. Defaults to 4. **/
	?tabSize:Int,
	/** Adds a Stage button to the first row of each change and receives that change when pressed. **/
	?onStage:CodeChange->Void,
	/** Adds a Revert button to the first row of each change and receives that change when pressed. **/
	?onRevert:CodeChange->Void,
	/** Additional actions after Stage and Revert on the first row of each change: `{label, ?icon, run}`. **/
	?hunkActions:Array<CodeDiffAction>,
	/** Inline labels at the ends of changed lines, such as revision authors. Only visible rows mount labels. **/
	?lineHints:IntoReactive<Array<CodeDiffHint>>,
	/** Replacement control icons, such as Remix icons matching the application. **/
	?icons:CodeDiffIconProps,
	/** Accessible name of the diff. **/
	?label:String,
	?id:String
}

/**
	A read-only text diff with syntax highlighting, line numbers and inline
	word changes. Long unchanged sections collapse into expandable rows.

	Inline layout combines removed and added lines in one column. Side-by-side
	layout shows synchronized original and modified columns, with filler rows
	to keep corresponding lines aligned. Fixed-height rows are pooled for
	large documents.

	Large comparisons run on `Worker`. The previous result remains visible
	until the new comparison completes.
**/
class CodeDiff extends Component<CodeDiffProps> {
	/** Number of changes in the current diff. **/
	public final changeCount = Signal.make(0);

	/** Zero-based index of the change last selected through navigation, or -1 before navigation. **/
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
	var hintAt:(Bool, Int)->Null<CodeDiffHint> = (_, _) -> null;
	var hasHints:Void->Bool = () -> false;

	/** Default stroke icons used when the application supplies no icon set. **/
	static final PREVIOUS:ashui.svg.Icon = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M6 15 L12 9 L18 15"/></svg>';

	static final NEXT:ashui.svg.Icon = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M6 9 L12 15 L18 9"/></svg>';

	static final STAGE:ashui.svg.Icon = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 5 V19 M5 12 H19"/></svg>';

	static final REVERT:ashui.svg.Icon = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M9 14 L4 9 L9 4"/><path d="M4 9 H15 A5 5 0 0 1 15 19 H11"/></svg>';

	static final FOLDED:ashui.svg.Icon = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M8 9 L12 5 L16 9"/><path d="M8 15 L12 19 L16 15"/></svg>';

	/** Combined line-count threshold for moving comparison to a worker thread. **/
	static inline var SYNCHRONOUS = 4000;

	/** Line-count threshold for building lexical checkpoints ahead, in `FILL_SLICE` batches per frame. **/
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
		var hints = Computed.make(() -> {
			var original = new Map<Int, CodeDiffHint>(), modified = new Map<Int, CodeDiffHint>();
			var supplied = props.lineHints == null ? [] : read(props.lineHints);
			if (supplied != null)
				for (hint in supplied) {
					if (hint == null || hint.line < 0 || hint.text == null || hint.text == "")
						continue;
					if (hint.side == "original")
						original.set(hint.line, hint);
					else if (hint.side == "modified")
						modified.set(hint.line, hint);
				}
			return {original: original, modified: modified};
		});
		hintAt = (original, line) -> original ? hints.get().original.get(line) : hints.get().modified.get(line);
		hasHints = () -> hints.get().original.iterator().hasNext() || hints.get().modified.iterator().hasNext();
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

	/** Builds one inline pane or two side-by-side panes with synchronized vertical scrolling. **/
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
				hint: hintAt,
				hasHints: hasHints,
				open: line -> {
					opened.set(line, true);
					rebuild();
				},
				step: delta -> goToChange(delta),
				current: currentChange,
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

	/** Builds the optional change counter and navigation buttons. **/
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

	/** Scrolls to the next change and wraps at the end. Uses the viewport position when the current change is offscreen. **/
	public function nextChange():Void
		goToChange(1);

	/** Scrolls to the previous change, wrapping from the first to the last. **/
	public function previousChange():Void
		goToChange(-1);

	/** Scrolls to a zero-based change index and selects it. Clamps indices to the available range. **/
	public function showChange(index:Int):Void {
		var set = rows.get();
		if (set == null || set.changes.length == 0 || panes.length == 0)
			return;
		var target = Std.int(Math.max(0, Math.min(set.changes.length - 1, index)));
		currentChange.set(target);
		for (p in panes)
			p.scrollToRow(set.rowOfChange(target));
	}

	/** Moves by `delta` changes, wrapping at both ends. Uses the viewport position when the current change is offscreen. **/
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

	/** Reveals a zero-based line in the modified text, expanding unchanged sections when needed. **/
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

	/** Expands all collapsed sections of unchanged lines. **/
	public function expandAll():Void {
		allOpen = true;
		rebuild();
	}

	/** Restores the default collapsed sections for the current comparison. **/
	public function collapseAll():Void {
		allOpen = false;
		opened.clear();
		rebuild();
	}

	/** Builds lexical checkpoints in frame-sized batches to reduce work on distant scroll jumps. **/
	function fillCheckpoints(text:CodeDiffText, generation:Int):Void {
		if (text.length < FILLING)
			return;
		function slice():Void
			if (generation == fills && !text.fill(FILL_SLICE))
				ashui.animation.AnimationScheduler.main.after(0, slice);
		ashui.animation.AnimationScheduler.main.after(0, slice);
	}

	/** Rebuilds rows for the current diff and layout while preserving expanded sections. **/
	function rebuild():Void {
		var c = compared;
		rows.set(c == null ? null : CodeDiffRows.build(c.original, c.modified, c.changes, layoutNow() == Split, props.context == null ? 3 : props.context,
			key -> allOpen || opened.exists(key)));
	}

	/** Returns the changes used to build the current rows. **/
	public function changes():Array<CodeChange>
		return compared == null ? [] : compared.changes;

	/** Returns visible row data for each pane, in display order. Used for inspection and tests. **/
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
