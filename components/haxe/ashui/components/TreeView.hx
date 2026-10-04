package ashui.components;

import ashui.input.Focus;
import ashui.input.Interaction;
import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.reactive.Computed;
import ashui.reactive.Signal;
import ashui.reactive.Watch;
import ashui.ui.Component;

typedef TreeViewProps = {
	/** The item chosen, by its value. A signal is read and written; a constant sets it once. **/
	?selected:IntoReactive<Null<String>>,
	?onSelect:String->Void,
	/** A line down each open item's children; true by default. **/
	?guides:Bool,
	?id:String
}

/**
	A tree of `TreeItem`s, each a row that chooses it and, with items of its
	own, opens and closes them: they grow in and fold away by layout
	animation, the rows below moving with them, its chevron turning. The
	arrows move among the rows shown, Right opens a row or steps into it,
	Left closes it or steps out to its parent, Home and End go to the first
	and last, and Enter or Space chooses. CSS: `.ui-tree` (`[data-guides]`),
	`.ui-tree-item` (`[data-state]` open or closed), `.ui-tree-row`
	(`[data-selected]`, `:hover`, `:focus-visible`), `.ui-tree-chevron`,
	`.ui-tree-icon`, `.ui-tree-label`, `.ui-tree-group` (`[data-state]`;
	closed, laid out at no height).
**/
class TreeView extends Component<TreeViewProps> {
	public var selected(default, null):Signal<Null<String>>;

	function render():Element {
		Library.use();
		selected = switch props.selected {
			case null: Signal.make((null : Null<String>));
			case Const(v): Signal.make(v);
			case Bound(s): s;
			case Derived(c):
				var s = Signal.make(c.get());
				new Watch(() -> c.get(), v -> s.set(v));
				s;
		}
		var chosen = selected;
		var roots:Array<TreeItem> = [for (c in children) if (Std.isOfType(c, TreeItem)) cast c];
		function choose(value:String) {
			chosen.set(value);
			if (props.onSelect != null)
				props.onSelect(value);
		}
		function bindAll(items:Array<TreeItem>, parent:Null<TreeItem>)
			for (item in items) {
				item.bind(chosen, choose, parent);
				bindAll(item.items, item);
			}
		bindAll(roots, null);
		// The rows shown, in order: an item's children only while it is open.
		function shown():Array<TreeItem> {
			var out = [];
			function walk(items:Array<TreeItem>)
				for (item in items) {
					out.push(item);
					if (item.expanded.get())
						walk(item.items);
				}
			walk(roots);
			return out;
		}
		var box = Library.part("ui-tree", null, ["guides" => (props.guides == false ? null : "" : Null<String>)], children, props.id);
		ashui.css.Identity.of(box.tree, box.node.id).setAttribute("role", "tree");
		Interaction.of(box.node).onKeyDown(e -> {
			var rows = shown();
			var at = Lambda.findIndex(rows, r -> r.row.focused.get());
			if (at < 0)
				return;
			var item = rows[at];
			var next:Null<TreeItem> = switch e.key {
				case Named(ArrowDown): rows[Std.int(Math.min(at + 1, rows.length - 1))];
				case Named(ArrowUp): rows[Std.int(Math.max(at - 1, 0))];
				case Named(Home): rows[0];
				case Named(End): rows[rows.length - 1];
				case Named(ArrowRight):
					if (item.items.length == 0) null else if (!item.expanded.get()) {
						item.expanded.set(true);
						null;
					} else item.items[0];
				case Named(ArrowLeft):
					if (item.items.length > 0 && item.expanded.get()) {
						item.expanded.set(false);
						null;
					} else item.parent;
				case Named(Enter) | Named(Space):
					choose(item.props.value);
					null;
				case _: return;
			}
			e.preventDefault();
			if (next != null && next != item)
				Focus.set(next.row, true);
		});
		return box;
	}
}

typedef TreeItemProps = {
	/** What choosing it chooses. **/
	value:String,
	/** Its row's text; elements other than items among its children follow it. **/
	?label:String,
	/** An icon before its label, SVG markup drawn in the text's colour. **/
	?icon:String,
	/** Whether its items show. A signal is read and written; a constant sets it once. **/
	?expanded:IntoReactive<Bool>,
	?id:String
}

/** One item of a tree: its row, and the items under it while it is open. **/
class TreeItem extends Component<TreeItemProps> {
	public var expanded(default, null):Signal<Bool>;

	/** The items under it. **/
	@:allow(ashui.components) var items(default, null):Array<TreeItem> = [];

	/** Its row's interaction, which has focus while the arrows are on it. **/
	@:allow(ashui.components) var row(default, null):Null<Interaction> = null;

	@:allow(ashui.components) var parent(default, null):Null<TreeItem> = null;

	final chosen = Signal.make((null : Null<Signal<Null<String>>>));
	var choose:Null<String->Void> = null;

	static var chevron:Null<ashui.svg.SvgDocument> = null;
	static final parsed = new Map<String, ashui.svg.SvgDocument>();

	function render():Element {
		expanded = switch props.expanded {
			case null: Signal.make(false);
			case Const(v): Signal.make(v);
			case Bound(s): s;
			case Derived(c):
				var s = Signal.make(c.get());
				new Watch(() -> c.get(), v -> s.set(v));
				s;
		}
		items = [for (c in children) if (Std.isOfType(c, TreeItem)) cast c];
		var others = [for (c in children) if (!Std.isOfType(c, TreeItem)) c];
		var open = expanded;
		var state = Computed.make(() -> (open.get() ? "open" : "closed" : Null<String>));
		var parts:Array<Element> = [];
		if (items.length > 0) {
			if (chevron == null)
				chevron = ashui.svg.SvgDocument.parse('<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m9 18 6-6-6-6"/></svg>');
			var c = new ashui.ui.Svg(chevron, {width: 14, height: 14});
			ashui.css.Identity.of(c.tree, c.node.id).setClasses(["ui-tree-chevron"]);
			parts.push(c);
		} else
			parts.push(Library.part("ui-tree-chevron-space", null, null, []));
		if (props.icon != null) {
			var doc = parsed.get(props.icon);
			if (doc == null)
				parsed.set(props.icon, doc = ashui.svg.SvgDocument.parse(props.icon));
			var icon = new ashui.ui.Svg(doc, {width: 16, height: 16});
			ashui.css.Identity.of(icon.tree, icon.node.id).setClasses(["ui-tree-icon"]);
			parts.push(icon);
		}
		var label:Array<Element> = props.label == null ? [] : [new ashui.ui.Text(props.label, {wrap: false})];
		parts.push(Library.part("ui-tree-label", null, null, label.concat(others)));
		var value = props.value;
		var ch = chosen;
		var rowBox = Library.part("ui-tree-row", null, ["selected" => Computed.make(() -> {
			var s = ch.get();
			(s != null && s.get() == value ? "" : null : Null<String>);
		})], parts);
		var identity = ashui.css.Identity.of(rowBox.tree, rowBox.node.id);
		identity.setAttribute("role", "treeitem");
		row = Interaction.of(rowBox.node).setFocusable(true).onClick(_ -> {
			if (choose != null)
				choose(value);
			if (items.length > 0)
				open.set(!open.get());
		});
		var inner:Array<Element> = [rowBox];
		if (items.length > 0) {
			var group = Library.part("ui-tree-group", null, ["state" => state], cast items);
			// Opening grows the group in, closing folds it away; the rows below move with it.
			ashui.animation.LayoutAnimation.attach(group.node);
			inner.push(group);
		}
		var box = Library.part("ui-tree-item", null, items.length > 0 ? ["state" => state] : null, inner, props.id);
		ashui.animation.LayoutAnimation.attach(box.node, {size: false});
		return box;
	}

	@:allow(ashui.components)
	function bind(selected:Signal<Null<String>>, onChoose:String->Void, up:Null<TreeItem>):Void {
		chosen.set(selected);
		choose = onChoose;
		parent = up;
	}
}
