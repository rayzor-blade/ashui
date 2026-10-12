package ashui.ui;

import ashui.css.Identity;
import ashui.layout.Element;
import ashui.layout.LayoutTree;
import ashui.layout.IntoReactive;
import ashui.layout.Node;
import ashui.layout.Prop;
import ashui.reactive.Owner;
import ashui.text.InlineFlow;

typedef TableProps = {
	?id:String
}

typedef ColgroupProps = {
	/** Columns it stands for when it holds no `<col>`; 1 by default. **/
	?span:Int
}

typedef ColProps = {
	/** Columns it stands for; 1 by default. **/
	?span:Int,

	/** Its width: layout units (`"120"`), a percentage of the table (`"25%"`), or a share of what is left (`"2*"`); sized by its cells by default. **/
	?width:String
}

typedef CellProps = {
	/** Columns it spans; 1 by default. **/
	?colspan:Int,

	/** Rows it spans within its row group; 1 by default, 0 through the group's end. **/
	?rowspan:Int,

	?id:String
}

/**
	HTML's `<table>`, built in: rows, `<tr>`, directly or in `<thead>`,
	`<tbody>` and `<tfoot>`, of cells, `<td>` and `<th>`, under an optional
	`<caption>`. Every row is a grid of the same columns, so cells line up
	down the table: as many as its widest row has, sized by their cells'
	unbreakable and one-line widths unless a `<col>` gives a width. A cell's
	`colspan` spans columns and its content constrains automatic tracks.
	`rowspan` spans rows in the same group, with 0 spanning its remaining rows.
	Rows that come or go later are laid out the same. Cells retain their row
	parents for CSS and input, including when they extend into a later row.

	Its look is the user-agent stylesheet's `table`, `caption`, `thead`,
	`tbody`, `tfoot`, `tr`, `th` and `td`.
**/
class Table extends Component<TableProps> {
	function render():Element {
		var box = new Div({tag: "table", id: props.id}, children);
		var cols:Array<Col> = [];
		for (c in children)
			if (Std.isOfType(c, Col))
				cols.push(cast c);
			else if (Std.isOfType(c, Colgroup))
				cols = cols.concat((cast c : Colgroup).cols());
		new TableColumns(box, cols);
		return box;
	}
}

private typedef TableRow = {
	var node:Node;
	var cells:Array<CellSlot>;
}

private typedef TableGroup = {
	var node:Node;
	var rows:Array<haxe.Int64>;
}

private typedef CellSlot = {
	var cell:Cell;
	var start:Int;
	var end:Int;
	var row:Int;
	var height:Int;
}

private typedef SpanningCell = {
	var cell:Cell;
	var start:Int;
	var end:Int;
}

/**
	Content sizing from blinc_ts's native/tables.ts, using existing Ashui flows
	and layout passes (Ashui 8fbda23, umbrella 8780d6b). Spanning-cell constraints
	are tracked in 4bcdb95. Rowspan placement uses shared native row layout,
	paint and hit traversal (471d54e / ABI bcec1a0); border-collapse/spacing
	remain in umbrella 8780d6b.
**/
private class TableColumns {
	final tree:LayoutTree;
	final id:haxe.Int64;
	final cols:Array<Col>;
	var rows:Array<TableRow> = [];
	var grids:Map<String, TableGroup> = [];
	var hidden:Map<String, Bool> = [];
	var placementDirty = false;
	var given:Array<Null<String>> = [];
	var min:Array<Float> = [];
	var max:Array<Float> = [];
	var spans:Array<SpanningCell> = [];
	var fixed:Array<Float> = [];
	var percentages:Array<{column:Int, fraction:Float}> = [];
	var needsWidth = false;
	var basisWidth = 0.0;
	var stops:Array<Void->Void> = [];
	var dirty = true;
	var template:Null<String>;

	public function new(box:Div, cols:Array<Col>) {
		tree = box.tree;
		id = box.node.id;
		this.cols = cols;
		ashui.layout.AfterChildren.watch(tree, "table " + haxe.Int64.toStr(id), parent -> within(tree, id, parent), refresh);
		InlineFlow.onMeasured(tree, afterMeasure);
		// Visibility only invalidates placement when it changes; row hover stays cheap (471d54e).
		var displayChanged = (node:Node) -> {
			if (node.tree != tree) return;
			var key = haxe.Int64.toStr(node.id);
			if (!hidden.exists(key)) return;
			if (hidden[key] != hiddenValue(node)) placementDirty = true;
			switch node.displayValue {
				case Bound(_) | Derived(_): placementDirty = true;
				case _:
			}
		};
		var flush = (t:LayoutTree) -> if (t == tree && placementDirty) refresh();
		Node.displayHooks.push(displayChanged);
		LayoutTree.flushHooks.push(flush);
		Owner.onCleanup(() -> {
			unsubscribe();
			Node.displayHooks.remove(displayChanged);
			LayoutTree.flushHooks.remove(flush);
			for (grid in grids) tree.setGridRows(grid.node.id, []);
			grids.clear();
		});
		refresh();
	}

	function unsubscribe():Void {
		for (stop in stops) stop();
		stops = [];
	}

	/** Cache rows and subscriptions when authored children change; no repeated tree walk during layout. **/
	function refresh():Void {
		placementDirty = false;
		unsubscribe();
		rows = [];
		hidden = [];
		given = [];
		for (c in cols)
			for (_ in 0...c.span())
				given.push(c.props.width == null || StringTools.trim(c.props.width) == "" ? null : track(c.props.width));
		var count = given.length;
		var nextGrids:Map<String, TableGroup> = [];
		for (group in groupsOf(tree, id)) {
			var occupied:Array<Int> = [], placed:Array<CellSlot> = [];
			for (y => r in group.rows) {
				var cells:Array<CellSlot> = [], x = 0;
				rows.push({node: new Node(r), cells: cells});
				var rowHidden = isHidden(r);
				for (node in tree.children(r)) {
					var cell = Cell.at(node);
					if (cell == null) continue;
					var cellHidden = isHidden(node);
					if (rowHidden || cellHidden) continue;
					var columns = cell.span(), height = cell.rowSpan(group.rows.length - y);
					// A colspan needs consecutive free slots, including earlier rowspans.
					while (true) {
						var collision = -1;
						for (i in x...x + columns) if (i < occupied.length && occupied[i] > y) { collision = i; break; }
						if (collision < 0) break;
						x = collision + 1;
					}
					var slot:CellSlot = {cell: cell, start: x, end: x + columns, row: y, height: height};
					cells.push(slot);
					placed.push(slot);
					while (occupied.length < slot.end) occupied.push(0);
					for (i in x...slot.end) occupied[i] = y + height;
					x = slot.end;
					count = Std.int(Math.max(count, x));
				}
			}
			var shared = Lambda.exists(placed, slot -> slot.height > 1);
			for (slot in placed) {
				slot.cell.place('grid-column', '${slot.start + 1} / span ${slot.end - slot.start}');
				slot.cell.place('grid-row', shared ? '${slot.row + 1} / span ${slot.height}' : null);
			}
			if (shared) {
				var key = haxe.Int64.toStr(group.node.id), previous = nextGrids.get(key);
				if (previous == null) nextGrids.set(key, group);
				else for (r in group.rows) previous.rows.push(r);
			}
		}
		for (key => grid in grids) if (!nextGrids.exists(key)) tree.setGridRows(grid.node.id, []);
		for (key => grid in nextGrids) {
			var previous = grids.get(key);
			var changed = previous == null || previous.rows.length != grid.rows.length;
			if (!changed) for (i in 0...grid.rows.length) if (grid.rows[i] != previous.rows[i]) { changed = true; break; }
			if (changed)
				if (!tree.setGridRows(grid.node.id, grid.rows)) throw "Table rows must be direct children of their group";
		}
		grids = nextGrids;
		while (given.length < count) given.push(null);
		min = [for (_ in given) 0.0];
		max = [for (_ in given) 0.0];
		fixed = [for (t in given) t != null && StringTools.endsWith(t, "px") ? Std.parseFloat(t) : 0.0];
		percentages = [for (i => t in given) if (t != null && StringTools.endsWith(t, "%")) {column: i, fraction: Std.parseFloat(t) / 100}];
		spans = [];
		needsWidth = false;
		for (row in rows) {
			for (slot in row.cells) {
				var cell = slot.cell, automatic = false;
				for (i in slot.start...slot.end) if (given[i] == null) automatic = true;
				if (automatic) {
					stops.push(cell.flow.onWidthsChanged(() -> dirty = true));
					if (cell.span() > 1) {
						spans.push({cell: cell, start: slot.start, end: slot.end});
						for (p in percentages) if (p.column >= slot.start && p.column < slot.end) needsWidth = true;
					}
				}
			}
		}
		// Smaller spans establish their constraints before wider or overlapping ones.
		spans.sort((a, b) -> (a.end - a.start) - (b.end - b.start));
		dirty = true;
		// New rows need the template even when it matches the previous rows' template.
		measure(true);
	}

	/** Percentage tracks change a span's available width on resize, without reshaping its text (4bcdb95). **/
	function afterMeasure():Bool {
		if (needsWidth && rows.length > 0) {
			var bounds = tree.getBounds(rows[0].node);
			if (bounds != null && bounds.width != basisWidth) {
				basisWidth = bounds.width;
				dirty = true;
			}
		}
		return dirty && measure();
	}

	function measure(force = false):Bool {
		dirty = false;
		for (i in 0...given.length) min[i] = max[i] = 0;
		for (row in rows) {
			for (slot in row.cells) {
				var cell = slot.cell, column = slot.start;
				var widths = given[column] == null && cell.span() == 1 ? cell.flow.widths() : null;
				if (widths != null && given[column] == null) {
					min[column] = Math.max(min[column], widths.min);
					max[column] = Math.max(max[column], widths.max);
				}
			}
		}
		for (p in percentages) fixed[p.column] = basisWidth * p.fraction;
		for (span in spans) {
			var widths = span.cell.flow.widths();
			if (widths == null) continue;
			constrain(span, min, widths.min);
			for (i in span.start...span.end) max[i] = Math.max(max[i], min[i]);
			constrain(span, max, widths.max);
		}
		var shares = Lambda.exists(given, t -> t != null && t.indexOf("fr") >= 0);
		var tracks = [for (i => t in given) t != null ? t :
			'minmax(${min[i]}px, ${shares ? Math.max(min[i], max[i]) + "px" : Math.max(max[i], 1) + "fr"})'];
		var next = tracks.length == 0 ? "none" : tracks.join(" ");
		if (!force && next == template) return false;
		template = next;
		for (row in rows) row.node.set(Prop.GridTemplateColumns, next);
		return true;
	}

	/**
		Share a spanning cell's missing width among automatic columns, by their
		preferred content widths; explicit tracks retain their settings (4bcdb95).
		Widths remain floating point, with the final allocation taking the remainder.
	**/
	function constrain(span:SpanningCell, sizes:Array<Float>, width:Float):Void {
		var total = 0.0, weight = 0.0, last = -1;
		for (i in span.start...span.end) {
			if (given[i] == null) {
				total += sizes[i];
				weight += Math.max(max[i], 1);
				last = i;
			} else total += fixed[i];
		}
		var missing = width - total;
		if (missing <= 0 || last < 0) return;
		var left = missing;
		for (i in span.start...span.end) if (given[i] == null) {
			var add = i == last ? left : missing * Math.max(max[i], 1) / weight;
			sizes[i] += add;
			left -= add;
		}
	}

	/** A column's track: its width, or an equal share that may shrink below its content. **/
	static function track(width:Null<String>):String {
		if (width == null || StringTools.trim(width) == "")
			return "minmax(0, 1fr)";
		var w = StringTools.trim(width);
		if (StringTools.endsWith(w, "*")) {
			var n = w.length == 1 ? 1 : Std.parseFloat(w.substr(0, w.length - 1));
			return 'minmax(0, ${n > 0 ? n : 1}fr)';
		}
		var n = Std.parseFloat(w);
		return n >= 0 ? (StringTools.endsWith(w, "%") ? n + "%" : n + "px") : "minmax(0, 1fr)";
	}

	static function typeOf(tree:LayoutTree, node:haxe.Int64, types:Array<String>):Bool {
		var identity = Identity.of(tree, node);
		return identity != null && Lambda.exists(identity.types, t -> types.indexOf(t) >= 0);
	}

	/** Whether a change of `parent`'s children moves this table's rows or cells. **/
	static function within(tree:LayoutTree, table:haxe.Int64, parent:haxe.Int64):Bool {
		if (parent == table)
			return true;
		if (!typeOf(tree, parent, ["thead", "tbody", "tfoot", "tr"]))
			return false;
		var up = tree.ancestors(parent);
		return up.length > 0 && (up[0] == table || (up.length > 1 && up[1] == table));
	}

	function isHidden(node:haxe.Int64):Bool {
		var identity = Identity.of(tree, node);
		var actual = identity == null ? new Node(node) : identity.node;
		var value = hiddenValue(actual), key = haxe.Int64.toStr(node);
		hidden.set(key, value);
		// Constants need no watch. Bound display follows the existing graph, never a polling loop.
		switch actual.displayValue {
			case Bound(_) | Derived(_):
				var watch = new ashui.reactive.Watch(() -> hiddenValue(actual), next -> if (hidden.get(key) != next) placementDirty = true);
				stops.push(watch.stop);
			case _:
		}
		return value;
	}

	static function hiddenValue(node:Node):Bool return switch node.displayValue {
		case Const(v): v == ashui.types.Style.Display.None;
		case Bound(s): s.get() == ashui.types.Style.Display.None;
		case Derived(c): c.get() == ashui.types.Style.Display.None;
		case null: false;
	};

	/** Sections and consecutive direct rows have independent occupied slots (471d54e). **/
	static function groupsOf(tree:LayoutTree, table:haxe.Int64):Array<TableGroup> {
		var groups:Array<TableGroup> = [], direct:Null<TableGroup> = null;
		for (c in tree.children(table)) {
			if (typeOf(tree, c, ["tr"])) {
				if (direct == null) {
					direct = {node: new Node(table), rows: []};
					groups.push(direct);
				}
				direct.rows.push(c);
			} else {
				direct = null;
				if (typeOf(tree, c, ["thead", "tbody", "tfoot"]))
					groups.push({node: new Node(c), rows: [for (r in tree.children(c)) if (typeOf(tree, r, ["tr"])) r]});
			}
		}
		return groups;
	}
}

/** HTML's `<colgroup>`: columns of a table, given by the `<col>`s it holds or by its `span`. Not drawn. **/
class Colgroup extends Component<ColgroupProps> {
	function render():Element
		return new Div({tag: "colgroup"});

	public function cols():Array<Col> {
		var held:Array<Col> = [for (c in children) if (Std.isOfType(c, Col)) cast c];
		if (held.length > 0)
			return held;
		return [new Col({span: props.span})];
	}
}

/** HTML's `<col>`: one or more columns of a table and their width. Not drawn. **/
class Col extends Component<ColProps> {
	function render():Element
		return new Div({tag: "col"});

	public function span():Int
		return props.span != null && props.span > 0 ? props.span : 1;
}

/** What `<td>` and `<th>` share: their spans, and a way for the table to find them. **/
abstract class Cell extends Component<CellProps> {
	static final byNode = new Map<String, Cell>();
	/** The existing cell flow also supplies its cached column measurements. **/
	public var flow(default, null):InlineFlow;

	function cell(tag:String):Element {
		var box = new Div({tag: tag, id: props.id}, children);
		flow = InlineFlow.attach(box);
		if (span() > 1) Identity.of(box.tree, box.node.id).setInline("grid-column", 'span ${span()}');
		var key = haxe.Int64.toStr(box.node.id);
		byNode.set(key, this);
		Owner.onCleanup(() -> byNode.remove(key));
		return box;
	}

	public function span():Int
		return props.colspan != null && props.colspan > 0 ? props.colspan : 1;

	/** Row spans stop at the group boundary, even for 0 or an oversized positive span. **/
	public function rowSpan(remaining:Int):Int
		return props.rowspan == 0 ? remaining : Std.int(Math.min(props.rowspan != null && props.rowspan > 0 ? props.rowspan : 1, remaining));

	/** Cached placement is an inline declaration, so cascade restyles cannot overwrite it. **/
	public function place(name:String, value:Null<String>):Void {
		var identity = Identity.of(tree, node.id), own = identity.inlineDeclarations();
		if ((own == null ? null : own.get(name)) != value) identity.setInline(name, value);
	}

	public static function at(node:haxe.Int64):Null<Cell>
		return byNode.get(haxe.Int64.toStr(node));
}

/** HTML's `<td>`: a cell of a table. **/
class Td extends Cell {
	function render():Element
		return cell("td");
}

/** HTML's `<th>`: a heading cell of a table. **/
class Th extends Cell {
	function render():Element
		return cell("th");
}
