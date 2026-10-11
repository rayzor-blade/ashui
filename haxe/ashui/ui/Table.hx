package ashui.ui;

import ashui.css.Identity;
import ashui.layout.Element;
import ashui.layout.LayoutTree;
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

	?id:String
}

/**
	HTML's `<table>`, built in: rows, `<tr>`, directly or in `<thead>`,
	`<tbody>` and `<tfoot>`, of cells, `<td>` and `<th>`, under an optional
	`<caption>`. Every row is a grid of the same columns, so cells line up
	down the table: as many as its widest row has, sized by their cells'
	unbreakable and one-line widths unless a `<col>` gives a width. A cell's
	`colspan` spans columns and its content constrains automatic tracks.
	Rows that come or go later are laid out the
	same. `rowspan` is not supported.

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
	var cells:Array<Cell>;
}

private typedef SpanningCell = {
	var cell:Cell;
	var start:Int;
	var end:Int;
}

/**
	Content sizing from blinc_ts's native/tables.ts, using existing Ashui flows
	and layout passes (Ashui 8fbda23, umbrella 8780d6b). Spanning-cell constraints
	are tracked in 4bcdb95. Rowspan needs the shared-row layout/paint prerequisite
	blinc_abi bcec1a0; border-collapse/spacing remain in umbrella 8780d6b.
**/
private class TableColumns {
	final tree:LayoutTree;
	final id:haxe.Int64;
	final cols:Array<Col>;
	var rows:Array<TableRow> = [];
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
		Owner.onCleanup(unsubscribe);
		refresh();
	}

	function unsubscribe():Void {
		for (stop in stops) stop();
		stops = [];
	}

	/** Cache rows and subscriptions when authored children change; no repeated tree walk during layout. **/
	function refresh():Void {
		unsubscribe();
		rows = [];
		given = [];
		for (c in cols)
			for (_ in 0...c.span())
				given.push(c.props.width == null || StringTools.trim(c.props.width) == "" ? null : track(c.props.width));
		var count = given.length;
		for (r in rowsOf(tree, id)) {
			var cells:Array<Cell> = [], n = 0;
			for (node in tree.children(r)) {
				var cell = Cell.at(node);
				if (cell == null) continue;
				cells.push(cell);
				n += cell.span();
			}
			rows.push({node: new Node(r), cells: cells});
			count = Std.int(Math.max(count, n));
		}
		while (given.length < count) given.push(null);
		min = [for (_ in given) 0.0];
		max = [for (_ in given) 0.0];
		fixed = [for (t in given) t != null && StringTools.endsWith(t, "px") ? Std.parseFloat(t) : 0.0];
		percentages = [for (i => t in given) if (t != null && StringTools.endsWith(t, "%")) {column: i, fraction: Std.parseFloat(t) / 100}];
		spans = [];
		needsWidth = false;
		for (row in rows) {
			var column = 0;
			for (cell in row.cells) {
				var end = column + cell.span(), automatic = false;
				for (i in column...end) if (given[i] == null) automatic = true;
				if (automatic) {
					stops.push(cell.flow.onWidthsChanged(() -> dirty = true));
					if (cell.span() > 1) {
						spans.push({cell: cell, start: column, end: end});
						for (p in percentages) if (p.column >= column && p.column < end) needsWidth = true;
					}
				}
				column = end;
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
			var column = 0;
			for (cell in row.cells) {
				var widths = given[column] == null && cell.span() == 1 ? cell.flow.widths() : null;
				if (widths != null && given[column] == null) {
					min[column] = Math.max(min[column], widths.min);
					max[column] = Math.max(max[column], widths.max);
				}
				column += cell.span();
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

	/** The rows of the table at `table`, its own and its sections'. **/
	static function rowsOf(tree:LayoutTree, table:haxe.Int64):Array<haxe.Int64> {
		var rows = [];
		for (c in tree.children(table))
			if (typeOf(tree, c, ["tr"]))
				rows.push(c);
			else if (typeOf(tree, c, ["thead", "tbody", "tfoot"]))
				for (r in tree.children(c))
					if (typeOf(tree, r, ["tr"]))
						rows.push(r);
		return rows;
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

/** What `<td>` and `<th>` share: their colspan, and a way for the table to find them. **/
abstract class Cell extends Component<CellProps> {
	static final byNode = new Map<String, Cell>();
	/** The existing cell flow also supplies its cached column measurements. **/
	public var flow(default, null):InlineFlow;

	function cell(tag:String):Element {
		var box = new Div({tag: tag, id: props.id}, children);
		flow = InlineFlow.attach(box);
		if (span() > 1)
			box.node.set(Prop.GridColumn, 'span ${span()}');
		var key = haxe.Int64.toStr(box.node.id);
		byNode.set(key, this);
		Owner.onCleanup(() -> byNode.remove(key));
		return box;
	}

	public function span():Int
		return props.colspan != null && props.colspan > 0 ? props.colspan : 1;

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
