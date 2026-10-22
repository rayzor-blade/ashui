package ashui.components.code;

import ashui.components.Library;
import ashui.components.code.CodeHints.CodeRect;
import ashui.components.code.CodeHistory.CodeEdit;
import ashui.css.Identity;
import ashui.input.Events.KeyEvent;
import ashui.input.Interaction;
import ashui.input.Scroll;
import ashui.layout.LayoutTree;
import ashui.reactive.Computed;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.reactive.Watch;
import ashui.ui.Div;
import ashui.ui.Text;
import ashui.ui.TopLayer;

/** One thing the list offers: what it shows, and what it puts in the text. **/
typedef CodeCompletion = {
	/** What the row says, and what is matched against what was typed, unless `filter` gives other text. **/
	var label:String;
	/** What goes into the text, `label` if left out. **/
	@:optional var insert:String;
	/** A signature or a type, dim and at the end of the row. **/
	@:optional var detail:String;
	/** Documentation, shown under the list while the row is the selected one; lines are kept, and it wraps. **/
	@:optional var docs:String;
	/** `function`, `method`, `class`, `type`, `interface`, `keyword`, `variable`, `field`, `property` or another, which only gives its letter. **/
	@:optional var kind:String;
	/** Text to match instead of `label`. **/
	@:optional var filter:String;
	/** The order among equal matches; otherwise the order they were given in. **/
	@:optional var sort:String;
	/** What else the choice changes, such as an import added at the top of the file. **/
	@:optional var more:Array<CodeEdit>;
}

/** What the list needs of the editor it is in. **/
typedef CompletionHost = {
	final tree:LayoutTree;
	final rectAt:Int->Null<CodeRect>;
	final text:Void->String;
	final caret:Void->Int;
	/** Puts `edits` in the text as one step. **/
	final apply:Array<CodeEdit>->Void;
}

private typedef Row = {item:CodeCompletion, index:Int};

/**
	A list of completions under the caret. The app gives it what the compiler or a language server offered and where the word being
	completed starts; the editor narrows it to what was typed since, as `from` to the caret, keeps the selected row in view, and
	puts the chosen one in the text. Up, Down, Page Up, Page Down, Home and End move the selection; Enter and Tab choose it;
	Escape closes the list, and so does the caret leaving the word, a character that is not part of a word, or nothing matching.
	Only visible rows and nearby ones are mounted; closing releases the offered items.
	A press on a row chooses it. Styled by `.ui-code-completion` and the classes in it, and by `--ui-code-completion-bg`,
	`--ui-code-completion-selected` and `--ui-code-completion-width`.
**/
class CodeCompletions {
	/** A row's height, in layout units, which the list scrolls by. **/
	static inline var ROW = 22.0;

	/** The rows the list holds at most, narrowed from however many were offered. **/
	static inline var MOST = 200;

	/** The rows seen at once. **/
	static inline var SEEN = 10;

	static inline var OVERSCAN = 2;

	final host:CompletionHost;
	var items:Array<CodeCompletion> = [];
	var from = 0;
	var entry:Null<ashui.ui.TopLayer.TopEntry> = null;
	var owner:Null<Owner> = null;
	var list:Null<Div> = null;
	var panel:Null<Div> = null;
	var scroll:Null<Scroll> = null;
	final rows = Signal.make(([] : Array<Row>));
	final selected = Signal.make(0);

	public function new(host:CompletionHost)
		this.host = host;

	public function isOpen():Bool
		return entry != null;

	/** Offers `items` for the word that starts at `from`; what has been typed since narrows them. **/
	public function show(offered:Array<CodeCompletion>, start:Int):Void {
		hide();
		items = offered;
		from = start;
		var matching = narrow();
		if (matching.length == 0)
			return hide();
		var anchor = host.rectAt(from);
		if (anchor == null || host.tree.root == null)
			return hide();
		rows.set(matching);
		selected.set(0);
		var scope = new Owner(host.tree);
		var built = scope.run(() -> build());
		panel = built;
		owner = scope;
		entry = TopLayer.open(host.tree, built, Beside(anchor.x, anchor.y, anchor.width, anchor.height, "bottom", 2, "start"), null, () -> {
			release(scope);
		}, false, true, true);
	}

	public function hide():Void {
		var open = entry;
		entry = null;
		if (open != null)
			open.close();
		if (owner != null)
			release(owner);
		clear();
	}

	/** Whether the pointer is over the list: a press on it takes focus from the editor, which must not close it. **/
	public function pointerOver():Bool {
		if (panel == null)
			return false;
		var b = host.tree.getScrolledBounds(panel.node), at = ashui.input.Pointer.at(host.tree);
		return b != null && at.x >= b.x && at.x < b.x + b.width && at.y >= b.y && at.y < b.y + b.height;
	}

	function release(scope:Owner):Void {
		scope.dispose();
		if (owner == scope) {
			owner = null;
			entry = null;
			clear();
		}
	}

	function clear():Void {
		if (items.length > 0)
			items = [];
		if (rows.get().length > 0)
			rows.set([]);
		selected.set(0);
		scroll = null;
		list = null;
		panel = null;
	}

	/** The text or the caret changed: narrows the list to what is typed now, or closes it. **/
	public function moved():Void {
		if (entry == null)
			return;
		var at = host.caret(), text = host.text();
		if (at < from || at > text.length)
			return hide();
		for (i in from...at)
			if (!isWordCharacter(text.charCodeAt(i)))
				return hide();
		var matching = narrow();
		if (matching.length == 0)
			return hide();
		rows.set(matching);
		selected.set(0);
		if (scroll != null)
			scroll.jumpTo(0, 0);
	}

	static function isWordCharacter(code:Int):Bool
		return code == "_".code || code == "$".code || (code >= "0".code && code <= "9".code) || (code >= "a".code && code <= "z".code) || (code >= "A".code && code <= "Z".code) || code > 127;

	/** What is typed since the word began: the text from `from` to the caret. **/
	function typed():String {
		var at = host.caret(), text = host.text();
		return at >= from && at <= text.length ? text.substring(from, at) : "";
	}

	/** The offered items that the typed text matches, best first: a prefix, then the starts of words, then letters in order. **/
	function narrow():Array<Row> {
		var query = typed().toLowerCase();
		var found:Array<{row:Row, score:Int, sort:String}> = [];
		for (i => item in items) {
			var score = score(item.filter == null ? item.label : item.filter, query);
			if (score >= 0)
				found.push({row: {item: item, index: i}, score: score, sort: item.sort == null ? "" : item.sort});
		}
		found.sort((a, b) -> a.score != b.score ? a.score - b.score : a.sort != b.sort ? (a.sort < b.sort ? -1 : 1) : a.row.index - b.row.index);
		return [for (f in found.slice(0, MOST)) f.row];
	}

	/** 0 for a prefix, 1 where the query's letters start words, 2 for letters in order, -1 for no match. **/
	static function score(label:String, query:String):Int {
		if (query == "")
			return 0;
		var lower = label.toLowerCase();
		if (StringTools.startsWith(lower, query))
			return 0;
		var at = 0, boundaries = 0, allBoundaries = true;
		for (i in 0...query.length) {
			var found = lower.indexOf(query.charAt(i), at);
			if (found < 0)
				return -1;
			var code = label.charCodeAt(found), previous = found == 0 ? 0 : label.charCodeAt(found - 1);
			var starts = found == 0 || !isWordCharacter(previous) || previous == "_".code || (code >= "A".code && code <= "Z".code && previous >= "a".code && previous <= "z".code);
			if (starts)
				boundaries++;
			else
				allBoundaries = false;
			at = found + 1;
		}
		return allBoundaries && boundaries == query.length ? 1 : 2;
	}

	/** The keys the open list takes; true when it took this one. **/
	public function key(event:KeyEvent):Bool {
		if (entry == null || event.control || event.alt || event.superKey)
			return false;
		var count = rows.get().length;
		switch event.key {
			case Named(ArrowDown):
				select(Std.int(Math.min(count - 1, selected.get() + 1)));
			case Named(ArrowUp):
				select(Std.int(Math.max(0, selected.get() - 1)));
			case Named(PageDown):
				select(Std.int(Math.min(count - 1, selected.get() + SEEN)));
			case Named(PageUp):
				select(Std.int(Math.max(0, selected.get() - SEEN)));
			case Named(Home) if (count > 0 && !event.shift):
				select(0);
			case Named(End) if (count > 0 && !event.shift):
				select(count - 1);
			case Named(Enter) | Named(Tab):
				event.preventDefault();
				accept(selected.get());
			case Named(Escape):
				hide();
			case _:
				return false;
		}
		event.preventDefault();
		return true;
	}

	function select(index:Int):Void {
		selected.set(index);
		if (scroll == null)
			return;
		var top = scroll.y.get(), at = index * ROW;
		if (at < top)
			scroll.jumpTo(0, at);
		else if (at + ROW > top + SEEN * ROW)
			scroll.jumpTo(0, at + ROW - SEEN * ROW);
	}

	/** Puts the `index`th row in the text, in place of what was typed since the word began. **/
	public function accept(index:Int):Void {
		var all = rows.get();
		if (index < 0 || index >= all.length)
			return;
		var item = all[index].item, at = host.caret();
		hide();
		var edits:Array<CodeEdit> = [{from: from, to: Std.int(Math.max(from, at)), text: item.insert == null ? item.label : item.insert}];
		if (item.more != null)
			edits = edits.concat(item.more);
		host.apply(edits);
	}

	function build():Div {
		var panel = Library.part("ui-code-completion");
		var shown = Library.part("ui-code-completion-list");
		list = shown;
		scroll = Scroll.attach(shown.node, false, true);
		scroll.visibility = "never";
		var scrolling = scroll;
		// Pixel movement only translates the list; crossing a row boundary changes its mounted range.
		var first = Computed.make(() -> Std.int(Math.max(0, Math.min(rows.get().length - 1, Math.floor(scrolling.y.get() / ROW)) - OVERSCAN)));
		var end = Computed.make(() -> Std.int(Math.min(rows.get().length, first.get() + SEEN + OVERSCAN * 2 + 1)));
		var visible = Computed.make(() -> rows.get().slice(first.get(), end.get()));
		shown.appendChild(new Div({height: Computed.make(() -> first.get() * ROW), flexShrink: 0}));
		shown.appendChild(<for {row in visible}>{rowOf(row)}</for>);
		shown.appendChild(new Div({height: Computed.make(() -> (rows.get().length - end.get()) * ROW), flexShrink: 0}));
		panel.appendChild(shown);
		var docs = Library.part("ui-code-completion-docs");
		var current = Computed.make(() -> { var all = rows.get(), i = selected.get(); i >= 0 && i < all.length ? all[i].item : null; });
		var docsScroll = Scroll.attach(docs.node, false, true);
		new Watch(() -> current.get(), _ -> docsScroll.jumpTo(0, 0));
		var lines = Computed.make(() -> { var item = current.get(); var text = item == null ? "" : item.docs != null ? item.docs : item.detail != null ? item.detail : ""; text == "" ? [] : text.split("\n"); });
		docs.appendChild(<for {line in lines}>{docLine(line)}</for>);
		panel.appendChild(docs);
		return panel;
	}

	function docLine(line:String):Text
		return <text class="ui-code-completion-docs-text">${line == "" ? " " : line}</text>;

	function rowOf(row:Row):Div {
		var item = row.item, index = rows.get().indexOf(row);
		var box = Library.part("ui-code-completion-row");
		var kind:Text = <text class="ui-code-completion-kind">${item.kind == null || item.kind == "" ? "·" : item.kind.charAt(0).toUpperCase()}</text>;
		if (item.kind != null)
			Identity.of(kind.tree, kind.node.id).setAttribute("data-kind", item.kind);
		box.appendChild(kind);
		box.appendChild(<text class="ui-code-text ui-code-completion-label">${item.label}</text>);
		if (item.detail != null)
			box.appendChild(<text class="ui-code-text ui-code-completion-detail">${firstLine(item.detail)}</text>);
		Identity.of(box.tree, box.node.id).bindBooleanAttribute("data-selected", Computed.make(() -> selected.get() == index));
		var i = Interaction.of(box.node);
		i.onPointerEnter(_ -> selected.set(index));
		i.onPointerDown(p -> {
			p.stopPropagation();
			accept(index);
		});
		return box;
	}

	static function firstLine(text:String):String {
		var end = text.indexOf("\n");
		return end < 0 ? text : text.substr(0, end);
	}
}
