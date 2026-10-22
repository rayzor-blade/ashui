package ashui.components.code;

import ashui.components.Library;
import ashui.components.code.CodeDiffRows;
import ashui.components.code.CodeDiffer.CodeChange;
import ashui.css.Identity;
import ashui.input.Interaction;
import ashui.input.Scroll;
import ashui.layout.Element;
import ashui.layout.LayoutTree;
import ashui.reactive.Computed;
import ashui.reactive.Signal;
import ashui.reactive.Watch;
import ashui.ui.Div;
import ashui.ui.Text;

/** What a pane shows of each row: the original's lines, the modified text's, or both in one column of rows. **/
enum CodeDiffSide {
	Original;
	Modified;
	Inline;
}

/**
	A button shown on the first row of each change, as "Stage hunk" or "Revert hunk" are; `run` is given the change. It shows the
	`label` as its text, or when it has an `icon`, shows only the icon and the label is its tooltip.
**/
typedef CodeDiffAction = {
	final label:String;
	final ?icon:ashui.svg.Icon;
	final run:CodeChange->Void;
}

/** Whether the text face is known, shared by the panes of one diff: until it is, there is no width to measure and no row to build. **/
class CodeDiffFont {
	public var dirty = true;
	public var revision = 0;

	public function new() {}
}

typedef CodeDiffPaneConfig = {
	final side:CodeDiffSide;
	final rows:Signal<Null<CodeDiffRows>>;
	final original:CodeMetrics;
	final modified:CodeMetrics;
	/** The lines of each text, tokenised as rows ask for them. **/
	final originalText:CodeDiffText;
	final modifiedText:CodeDiffText;
	final tabSize:Int;
	/** Counts the times what the rows are measured against changed. **/
	final revision:Signal<Int>;
	final font:CodeDiffFont;
	final lineNumbers:Bool;
	/** Buttons for the first row of each change; none for a pane that has no room for them. **/
	final actions:Array<CodeDiffAction>;
	/** Called with the modified line a placeholder's hidden run starts at, when the placeholder is pressed. **/
	final open:Int->Void;
	/** Called with 1 or -1 when the pane has focus and F7 or Shift+F7 is pressed, to go to the next change or the previous. **/
	final step:Int->Void;
	final label:String;
	/** The mark at the start of the row of a folded run. **/
	final foldIcon:ashui.svg.Icon;
}

private typedef Run = {text:String, kind:String, x:Single};
private typedef Mark = {x:Single, width:Single, kind:String};
/** A pooled token element: the `index`th run of its `kind` in the row its slot shows. **/
private typedef Token = {kind:String, index:Int};
private typedef Shown = {
	row:Int,
	top:Single,
	kind:String,
	change:Int,
	first:Bool,
	hidden:Int,
	label:String,
	oldNumber:String,
	newNumber:String,
	sign:String,
	byKind:Map<String, Array<Run>>,
	width:Single,
	marks:Array<Mark>,
	rows:CodeDiffRows,
	stamp:Int
};

/**
	One column of a diff, scrolling on its own: a viewport of rows that are all one height. Rows are pooled as the code editor's
	are (row `r` is shown by slot `r % capacity`, so scrolling a line changes the bindings of the one slot whose row changed and
	builds nothing), with a gutter of line numbers that stays at the left edge, a background for each kind of row, the changed
	words marked behind the text, and a placeholder that opens a hidden run of unchanged lines when it is pressed.
**/
class CodeDiffPane {
	/** Between the gutter and the text, and the room kept to the right of the longest line. **/
	static inline var PAD = 8.0;

	/** The column for the "+" or "-" of a changed line. **/
	static inline var SIGN = 16.0;

	public final view:Div;
	public var scroll(default, null):Null<Scroll>;
	public final viewHeight = Signal.make(320.0);
	public final viewWidth = Signal.make(600.0);
	final config:CodeDiffPaneConfig;
	final slotShown:Array<Signal<Null<Shown>>> = [];
	final slotTokens:Array<Signal<Array<Token>>> = [];
	final slotPools:Array<Map<String, Array<Token>>> = [];
	final slotKinds:Array<Array<String>> = [];
	final distributed:Array<Null<Shown>> = [];
	/** False until the viewport exists: the window of rows is worked out from its scroll. **/
	final mounted = Signal.make(false);
	final contentWidth:Computed<Single>;
	final contentHeight:Computed<Single>;
	final gutterWidth:Computed<Single>;
	var cached:Array<Shown> = [];

	public function new(config:CodeDiffPaneConfig) {
		this.config = config;
		var revision = config.revision, rows = config.rows, font = config.font, metrics = config.original;
		var rowHeight = Computed.make(() -> {
			revision.get();
			(metrics.lineHeight : Single);
		});
		var numbers = config.lineNumbers ? (config.side == Inline ? 2 : 1) : 0;
		gutterWidth = Computed.make(() -> {
			revision.get();
			var most = Std.int(Math.max(1, Math.max(config.originalText.length, config.modifiedText.length)));
			var column = Std.string(most).length * metrics.characterWidth + 14;
			(numbers * column + SIGN + 4 : Single);
		});
		contentHeight = Computed.make(() -> {
			revision.get();
			var set = rows.get();
			((set == null ? 0 : set.count) * metrics.lineHeight : Single);
		});
		contentWidth = Computed.make(() -> {
			revision.get();
			var set = rows.get();
			var widest = set == null ? 0 : switch config.side {
				case Original: set.widestColumn(true, config.tabSize);
				case Modified: set.widestColumn(false, config.tabSize);
				case Inline: Std.int(Math.max(set.widestColumn(true, config.tabSize), set.widestColumn(false, config.tabSize)));
			}
			(Math.max(viewWidth.get(), gutterWidth.get() + PAD * 2 + widest * metrics.characterWidth + 2) : Single);
		});
		var firstRow = Signal.make(0), endRow = Signal.make(0);
		new Watch(() -> windowStart(), row -> firstRow.set(row));
		new Watch(() -> windowEnd(), row -> endRow.set(row));
		var window = Computed.make(() -> shownRows(firstRow.get(), endRow.get()));
		// Kept across height changes, as the editor keeps its slots: a new modulus would reassign every visible row.
		var capacity = Signal.make(1);
		new Watch(() -> {
			revision.get();
			var set = rows.get();
			{rows: set == null ? 0 : set.count, window: Std.int(Math.ceil(viewHeight.get() / Math.max(1, metrics.lineHeight))) + 9};
		}, size -> capacity.set(Std.int(Math.max(1, Math.min(size.rows, Math.max(capacity.get(), size.window))))));
		var slots = Computed.make(() -> [for (i in 0...capacity.get()) i]);
		new Watch(() -> {
			capacity.get();
			window.get();
		}, _ -> distribute(window.get(), capacity.get()));
		var left = Computed.make(() -> (gutterWidth.get() + PAD : Single));
		var content = <div class="ui-code-diff-content" width={contentWidth} height={contentHeight}>
			<for {i in slots}>{rowSlot(i, left, rowHeight)}</for>
			<div class="ui-code-diff-gutter" left={Computed.make(() -> {
				revision.get();
				(scroll == null ? 0 : scroll.x.get() : Single);
			})} width={gutterWidth} height={contentHeight}>
				<for {i in slots}>{gutterSlot(i, rowHeight, numbers)}</for>
			</div>
		</div>;
		view = Library.part("ui-code-diff-viewport", null, null, [content]);
		scroll = Scroll.attach(view.node, true, true);
		var identity = Identity.of(view.tree, view.node.id);
		identity.setAttribute("role", "region").setAttribute("aria-label", config.label);
		Interaction.of(view.node).setFocusable(true).onKeyDown(event -> switch event.key {
			case Named(F7) if (!event.control && !event.superKey && !event.alt):
				event.preventDefault();
				config.step(event.shift ? -1 : 1);
			case _:
		});
		mounted.set(true);
	}

	function windowStart():Int {
		config.revision.get();
		mounted.get();
		if (config.font.dirty || scroll == null)
			return 0;
		return Std.int(Math.max(0, Math.floor(scroll.y.get() / config.original.lineHeight) - 3));
	}

	function windowEnd():Int {
		config.revision.get();
		mounted.get();
		var set = config.rows.get();
		if (config.font.dirty || set == null || scroll == null)
			return 0;
		return Std.int(Math.min(set.count, Math.ceil((scroll.y.get() + viewHeight.get()) / config.original.lineHeight) + 3));
	}

	/** The rows from `first` to `end`, as what a slot shows of each; one already made is kept, so a scroll makes only the rows that came into the window. **/
	function shownRows(first:Int, end:Int):Array<Shown> {
		config.revision.get();
		var set = config.rows.get();
		if (config.font.dirty || set == null)
			return [];
		var result:Array<Shown> = [], stamp = config.font.revision;
		for (r in first...(end < set.count ? end : set.count)) {
			var found:Null<Shown> = null;
			for (old in cached)
				if (old.row == r && old.rows == set && old.stamp == stamp) {
					found = old;
					break;
				}
			result.push(found != null ? found : shown(set, r, stamp));
		}
		cached = result;
		return result;
	}

	function shown(set:CodeDiffRows, r:Int, stamp:Int):Shown {
		var o = set.originalAt(r), m = set.modifiedAt(r), change = set.changeAt(r), hidden = set.hiddenAt(r), side = config.side;
		var kind:String, fromOriginal:Bool;
		if (hidden > 0) {
			kind = "placeholder";
			fromOriginal = false;
		} else
			switch side {
				case Original:
					fromOriginal = true;
					kind = o < 0 ? "filler" : change >= 0 ? "removed" : "context";
				case Modified:
					fromOriginal = false;
					kind = m < 0 ? "filler" : change >= 0 ? "added" : "context";
				case Inline:
					fromOriginal = m < 0;
					kind = change < 0 ? "context" : m < 0 ? "removed" : "added";
			}
		var byKind = new Map<String, Array<Run>>(), marks:Array<Mark> = [], width = 0.0;
		if (hidden == 0 && kind != "filler") {
			var metrics = fromOriginal ? config.original : config.modified, line = (fromOriginal ? config.originalText : config.modifiedText).line(fromOriginal ? o : m);
			var measured = metrics.measure(line), runs:Array<Run> = [];
			if (line.tokenCount == 0)
				runs.push({text: measured.expanded, x: 0, kind: "plain"});
			else
				for (t in 0...line.tokenCount) {
					var from = line.tokenFrom(t), to = line.tokenTo(t);
					runs.push({
						text: measured.expanded.substring(measured.columns[from], measured.columns[to]),
						x: (metrics.xAt(line, from) : Single),
						kind: line.tokenKind(t)
					});
				}
			for (run in runs) {
				var list = byKind.get(run.kind);
				if (list == null)
					byKind.set(run.kind, list = []);
				list.push(run);
			}
			width = measured.width;
			var words = set.wordsAt(r, fromOriginal);
			if (words != null)
				for (w in words) {
					var x = metrics.xAt(line, w.from), right = metrics.xAt(line, w.to);
					if (right > x)
						marks.push({x: (x : Single), width: (Math.max(2, right - x) : Single), kind: fromOriginal ? "removed" : "added"});
				}
		}
		return {
			row: r,
			top: (r * config.original.lineHeight : Single),
			kind: kind,
			change: change,
			first: set.firstOfChange(r),
			hidden: hidden,
			label: hidden > 0 ? '$hidden unchanged lines' : "",
			oldNumber: side != Modified && o >= 0 && hidden == 0 ? Std.string(o + 1) : "",
			newNumber: side != Original && m >= 0 && hidden == 0 ? Std.string(m + 1) : "",
			sign: kind == "removed" ? "-" : kind == "added" ? "+" : "",
			byKind: byKind,
			width: (width : Single),
			marks: marks,
			rows: set,
			stamp: stamp
		};
	}

	function slotAt(i:Int):Signal<Null<Shown>> {
		while (slotShown.length <= i) {
			slotShown.push(Signal.make((null : Null<Shown>)));
			slotTokens.push(Signal.make(([] : Array<Token>)));
			distributed.push(null);
			slotPools.push(new Map());
			slotKinds.push([]);
		}
		return slotShown[i];
	}

	/** Gives each slot the row of the window it shows, setting only the slots whose row is another one. **/
	function distribute(list:Array<Shown>, capacity:Int):Void {
		var next:Array<Null<Shown>> = [for (_ in 0...capacity) null];
		for (row in list)
			next[row.row % capacity] = row;
		for (i in 0...Std.int(Math.max(capacity, distributed.length))) {
			var row = i < capacity ? next[i] : null;
			if (i >= distributed.length && row == null)
				continue;
			slotAt(i);
			if (distributed[i] == row)
				continue;
			distributed[i] = row;
			slotShown[i].set(row);
			fitTokens(i, row);
		}
	}

	/** Gives slot `i` the token elements of each kind that `row` needs: it keeps what it has, grows when a row has more, and gives back when a row needs under a quarter. **/
	function fitTokens(i:Int, row:Null<Shown>):Void {
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

	// A slot with no row is hidden, not faded: a group at no opacity is still drawn, into a layer of the window's size.
	function rowSlot(i:Int, left:Computed<Single>, rowHeight:Computed<Single>):Element {
		var row = slotAt(i);
		var visible = Computed.make(() -> (row.get() != null ? ashui.types.Style.Visibility.Visible : ashui.types.Style.Visibility.Hidden : ashui.types.Style.Visibility));
		var top = Computed.make(() -> {
			var r = row.get();
			(r == null ? 0 : r.top : Single);
		});
		var kind = Computed.make(() -> {
			var r = row.get();
			(r == null ? null : r.kind : Null<String>);
		});
		var marks = Computed.make(() -> {
			var r = row.get();
			r == null ? [] : r.marks;
		});
		var tokens = Computed.make(() -> slotTokens[i].get());
		var placeholder = Computed.make(() -> {
			var r = row.get();
			(r != null && r.hidden > 0 ? ashui.types.Style.Visibility.Visible : ashui.types.Style.Visibility.Hidden : ashui.types.Style.Visibility);
		});
		var label = Computed.make(() -> {
			var r = row.get();
			r == null ? "" : r.label;
		});
		var plain = Computed.make(() -> {
			var r = row.get();
			(r != null && r.hidden == 0 ? ashui.types.Style.Visibility.Visible : ashui.types.Style.Visibility.Hidden : ashui.types.Style.Visibility);
		});
		// A pressed placeholder opens its run; the element is always there and answers only while its slot's row is a placeholder.
		var folded = Computed.make(() -> {
			var r = row.get();
			r != null && r.hidden > 0;
		});
		var fold:Div = <div class="ui-code-diff-fold" left={left} height={rowHeight} visibility={placeholder}>
			<if {folded.get()}>${foldIcon()}</if>
			<text class="ui-code-text ui-code-diff-fold-text">${label.get()}</text>
		</div>;
		Interaction.of(fold.node).onClick(event -> {
			var r = row.get();
			if (r != null && r.hidden > 0) {
				event.stopPropagation();
				config.open(r.rows.modifiedAt(r.row));
			}
		});
		var element:Div = <div class="ui-code-diff-row" left={0} top={top} width={contentWidth} height={rowHeight} visibility={visible}>
			<div class="ui-code-diff-line" left={left} height={rowHeight} visibility={plain}>
				<for {m in marks}>{wordMark(m, rowHeight)}</for>
				<for {t in tokens}>{tokenSlot(row, t)}</for>
			</div>
			${fold}
			<if {config.actions.length > 0}>${actionsSlot(row)}</if>
		</div>;
		Identity.of(element.tree, element.node.id).bindAttribute("data-kind", kind);
		return element;
	}

	/** The mark at the start of a folded run's row. **/
	function foldIcon():Element {
		var glyph = new ashui.components.Icon({document: config.foldIcon});
		Identity.of(glyph.tree, glyph.node.id).addClasses(["ui-code-diff-fold-icon"]);
		return glyph;
	}

	function wordMark(mark:Mark, rowHeight:Computed<Single>):Element {
		var element:Div = <div class="ui-code-diff-word" left={mark.x} width={mark.width} height={rowHeight} />;
		Identity.of(element.tree, element.node.id).setAttribute("data-kind", mark.kind);
		return element;
	}

	function tokenSlot(row:Signal<Null<Shown>>, token:Token):Element {
		function run(r:Null<Shown>):Null<Run> {
			var list = r == null ? null : r.byKind.get(token.kind);
			return list != null && token.index < list.length ? list[token.index] : null;
		}
		var left = Computed.make(() -> {
			var u = run(row.get());
			(u == null ? 0 : u.x : Single);
		});
		var content = Computed.make(() -> {
			var u = run(row.get());
			u == null ? "" : u.text;
		});
		var text:Text = <text class="ui-code-text ui-code-token" left={left} top={0}>${content.get()}</text>;
		Identity.of(text.tree, text.node.id).setAttribute("data-token", token.kind);
		return text;
	}

	function gutterSlot(i:Int, rowHeight:Computed<Single>, numbers:Int):Element {
		var row = slotAt(i);
		var visible = Computed.make(() -> (row.get() != null ? ashui.types.Style.Visibility.Visible : ashui.types.Style.Visibility.Hidden : ashui.types.Style.Visibility));
		var top = Computed.make(() -> {
			var r = row.get();
			(r == null ? 0 : r.top : Single);
		});
		var kind = Computed.make(() -> {
			var r = row.get();
			(r == null ? null : r.kind : Null<String>);
		});
		var oldNumber = Computed.make(() -> {
			var r = row.get();
			r == null ? "" : r.oldNumber;
		});
		var newNumber = Computed.make(() -> {
			var r = row.get();
			r == null ? "" : r.newNumber;
		});
		var sign = Computed.make(() -> {
			var r = row.get();
			r == null ? "" : r.sign;
		});
		var column = Computed.make(() -> {
			config.revision.get();
			(Std.string(Std.int(Math.max(1, Math.max(config.originalText.length, config.modifiedText.length)))).length * config.original.characterWidth + 8 : Single);
		});
		var element:Div = <div class="ui-code-diff-gutter-line" top={top} height={rowHeight} width={gutterWidth} visibility={visible}>
			<if {config.lineNumbers && config.side != Modified}><text class="ui-code-text ui-code-diff-number" width={column}>${oldNumber.get()}</text></if>
			<if {config.lineNumbers && config.side != Original}><text class="ui-code-text ui-code-diff-number" width={column}>${newNumber.get()}</text></if>
			<text class="ui-code-text ui-code-diff-sign">${sign.get()}</text>
		</div>;
		Identity.of(element.tree, element.node.id).bindAttribute("data-kind", kind);
		return element;
	}

	/** The buttons of the first row of each change, at the right edge of what is on screen; the stylesheet shows them while the pointer is over the row. **/
	function actionsSlot(row:Signal<Null<Shown>>):Element {
		var first = Computed.make(() -> {
			var r = row.get();
			(r != null && r.first && r.hidden == 0 ? "true" : null : Null<String>);
		});
		var width = 8.0;
		for (a in config.actions)
			width += a.icon != null ? 28.0 : a.label.length * 7.0 + 28;
		var left = Computed.make(() -> {
			config.revision.get();
			(Math.max(0, (scroll == null ? 0 : scroll.x.get()) + viewWidth.get() - width - 12) : Single);
		});
		var buttons:Array<Element> = [for (a in config.actions) actionButton(row, a)];
		var box = new Div({classes: ["ui-code-diff-actions"], left: left, width: (width : Single)}, buttons);
		Identity.of(box.tree, box.node.id).bindAttribute("data-first", first);
		return box;
	}

	function actionButton(row:Signal<Null<Shown>>, action:CodeDiffAction):Element {
		var button:Div;
		if (action.icon != null) {
			var glyph = new ashui.components.Icon({document: action.icon});
			Identity.of(glyph.tree, glyph.node.id).addClasses(["ui-code-diff-action-glyph"]);
			button = new Div({classes: ["ui-code-diff-action", "ui-code-diff-action-icon"]}, [glyph]);
		} else
			button = <div class="ui-code-diff-action"><text class="ui-code-diff-action-label">${action.label}</text></div>;
		Interaction.of(button.node).setFocusable(true).onClick(event -> {
			var r = row.get();
			if (r != null && r.first && r.change >= 0) {
				event.stopPropagation();
				action.run(r.rows.changes[r.change]);
			}
		});
		Identity.of(button.tree, button.node.id).setAttribute("role", "button").setAttribute("aria-label", action.label);
		// An icon says nothing by itself: the label is its tooltip.
		return action.icon != null ? new ashui.components.Tooltip({label: action.label, side: "top", delay: 0.3}, [button]) : button;
	}

	/** Reads the viewport's size and keeps the scroll inside the content; true when anything changed. **/
	public function measure(tree:LayoutTree):Bool {
		var bounds = tree.getBounds(view.node);
		// A pane with no layout box keeps its last usable size, so hiding it does not discard its rows.
		if (bounds == null || bounds.width <= 0 || bounds.height <= 0)
			return false;
		var changed = false;
		if (viewHeight.get() != bounds.height) {
			viewHeight.set(bounds.height);
			changed = true;
		}
		if (viewWidth.get() != bounds.width) {
			viewWidth.set(bounds.width);
			changed = true;
		}
		var x = Math.min(scroll.x.get(), Math.max(0, contentWidth.get() - bounds.width));
		var y = Math.min(scroll.y.get(), Math.max(0, contentHeight.get() - bounds.height));
		if (x != scroll.x.get() || y != scroll.y.get()) {
			scroll.jumpTo(x, y);
			changed = true;
		}
		return changed;
	}

	/** The row at the top of the view. **/
	public function topRow():Int
		return Std.int(Math.max(0, Math.floor(scroll.y.get() / Math.max(1, config.original.lineHeight))));

	/** Whether the whole of `row` is in the view. **/
	public function rowVisible(row:Int):Bool {
		var lh = config.original.lineHeight, top = row * lh;
		return top >= scroll.y.get() && top + lh <= scroll.y.get() + viewHeight.get();
	}

	/** Scrolls so `row` is a third of the view from the top, or in the middle when `centered`. **/
	public function scrollToRow(row:Int, centered = false):Void {
		var lh = config.original.lineHeight, h = viewHeight.get();
		var target = row * lh - (centered ? (h - lh) / 2 : h / 3);
		scroll.jumpTo(scroll.x.get(), Math.max(0, target));
	}

	/** The rows now in slots, in row order, with their kind and the text they show; for checks. **/
	public function shownNow():Array<{row:Int, kind:String, text:String, oldNumber:String, newNumber:String}> {
		var result = [];
		for (s in distributed)
			if (s != null) {
				var text = new StringBuf();
				var runs = [for (list in s.byKind) for (run in list) run];
				runs.sort((a, b) -> a.x < b.x ? -1 : a.x > b.x ? 1 : 0);
				for (run in runs)
					text.add(run.text);
				result.push({row: s.row, kind: s.kind, text: s.hidden > 0 ? s.label : text.toString(), oldNumber: s.oldNumber, newNumber: s.newNumber});
			}
		result.sort((a, b) -> a.row - b.row);
		return result;
	}
}
