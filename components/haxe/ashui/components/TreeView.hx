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
	/** Selected item value, or null. A supplied signal is read and updated; a constant sets the initial selection. **/
	?selected:IntoReactive<Null<String>>,
	?onSelect:String->Void,
	/** Shows guide lines along expanded child groups. Defaults to true. **/
	?guides:Bool,
	?id:String
}

/**
	A selectable tree with animated expansion and collapse.

	Each `TreeItem` has a row and optional children. Up/Down navigate visible
	rows; Right expands or enters children, and Left collapses or moves to
	the parent. Home/End reach the first or last row; Enter/Space select.
	Expanding animates child height and the positions of later rows.

	CSS: `.ui-tree[data-guides]`, `.ui-tree-item[data-state]`,
	`.ui-tree-row` with `[data-selected]`, `:hover`, and `:focus-visible`,
	plus `.ui-tree-chevron`, `.ui-tree-icon`, `.ui-tree-label`, and
	`.ui-tree-group[data-state]`. Closed groups have zero height.
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
		for (item in roots)
			item.bindTree(chosen, choose, null);
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
					if (!item.branch()) null else if (!item.expanded.get()) {
						item.expanded.set(true);
						null;
					} else item.items[0];
				case Named(ArrowLeft):
					if (item.branch() && item.expanded.get()) {
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
	/** Value stored when this item is selected. **/
	value:String,
	/** Row label. Non-item children appear after the label. **/
	?label:String,
	/** Leading SVG icon using the text color. Accepts a compiled SVG document or SVG markup. **/
	?icon:ashui.svg.Icon,
	/** Whether children are expanded. A supplied signal is read and updated; a constant sets the initial state. **/
	?expanded:IntoReactive<Bool>,
	/**
		Creates child items once, on first expansion. Useful for large folders.
		Only tree items are retained from the result. Before loading, the row
		shows a chevron without creating the children.
	**/
	?load:Void->Array<Element>,
	?id:String
}

/**
	A tree row with optional child items.
	Use `load` for children that should be created on first expansion,
	such as `<tree-item load={() -> entries(dir)}/>` in a file explorer.
**/
class TreeItem extends Component<TreeItemProps> {
	public var expanded(default, null):Signal<Bool>;

	/** Child tree items. **/
	@:allow(ashui.components) var items(default, null):Array<TreeItem> = [];

	/** Row interaction used by keyboard navigation. **/
	@:allow(ashui.components) var row(default, null):Null<Interaction> = null;

	@:allow(ashui.components) var parent(default, null):Null<TreeItem> = null;

	final chosen = Signal.make((null : Null<Signal<Null<String>>>));
	var choose:Null<String->Void> = null;

	static var chevron:Null<ashui.svg.SvgDocument> = null;

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
		if (branch()) {
			if (chevron == null)
				chevron = ashui.svg.SvgDocument.of(<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m9 18 6-6-6-6"/></svg>);
			var c = new ashui.ui.Svg(chevron, {width: 14, height: 14});
			ashui.css.Identity.of(c.tree, c.node.id).setClasses(["ui-tree-chevron"]);
			parts.push(c);
		} else
			parts.push(Library.part("ui-tree-chevron-space", null, null, []));
		if (props.icon != null) {
			var icon = new ashui.ui.Svg(props.icon, {width: 16, height: 16});
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
			if (branch())
				open.set(!open.get());
		});
		var inner:Array<Element> = [rowBox];
		if (branch()) {
			var group = Library.part("ui-tree-group", null, ["state" => state], cast items);
			// Opening grows the group in, closing folds it away; the rows below move with it.
			ashui.animation.LayoutAnimation.attach(group.node);
			inner.push(group);
			if (props.load != null) {
				// Built under this item's owner, so they leave with it, the first time it opens.
				var made = false;
				new Watch(() -> open.get(), on -> {
					if (!on || made)
						return;
					made = true;
					items = [for (c in owner.run(props.load)) if (Std.isOfType(c, TreeItem)) cast c];
					for (item in items)
						item.bindTree(chosen.get(), choose, this);
					group.tree.replaceChildren(group.node.id, [for (item in items) item.node.id]);
				});
			}
		}
		var box = Library.part("ui-tree-item", null, branch() ? ["state" => state] : null, inner, props.id);
		ashui.animation.LayoutAnimation.attach(box.node, {size: false});
		return box;
	}

	/** Returns whether this item has children or can load them on expansion. **/
	@:allow(ashui.components)
	function branch():Bool
		return items.length > 0 || props.load != null;

	/** Connects this item and its descendants to selection handlers and parent navigation. **/
	@:allow(ashui.components)
	function bindTree(selected:Null<Signal<Null<String>>>, onChoose:Null<String->Void>, up:Null<TreeItem>):Void {
		chosen.set(selected);
		choose = onChoose;
		parent = up;
		for (item in items)
			item.bindTree(selected, onChoose, this);
	}
}
