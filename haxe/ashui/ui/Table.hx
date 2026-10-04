package ashui.ui;

import ashui.css.Identity;
import ashui.layout.Element;
import ashui.layout.LayoutTree;
import ashui.layout.Node;
import ashui.layout.Prop;
import ashui.reactive.Owner;

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

	/** Its width: layout units (`"120"`), a percentage of the table (`"25%"`), or a share of what is left (`"2*"`); an equal share by default. **/
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
	down the table: as many as its widest row has, each an equal share of
	the width unless a `<col>` in a `<colgroup>` gives it one. A cell's
	`colspan` spans columns. Rows that come or go later are laid out the
	same. `rowspan` is not supported.

	Its look is the user-agent stylesheet's `table`, `caption`, `thead`,
	`tbody`, `tfoot`, `tr`, `th` and `td`.
**/
class Table extends Component<TableProps> {
	function render():Element {
		var box = new Div({tag: "table", id: props.id}, children);
		var tree = box.tree, id = box.node.id;
		var cols:Array<Col> = [];
		for (c in children)
			if (Std.isOfType(c, Col))
				cols.push(cast c);
			else if (Std.isOfType(c, Colgroup))
				cols = cols.concat((cast c : Colgroup).cols());
		function layOut() {
			var rows = rowsOf(tree, id);
			var count = 0;
			for (c in cols)
				count += c.span();
			for (r in rows) {
				var n = 0;
				for (cell in tree.children(r)) {
					var c = Cell.at(cell);
					n += c == null ? 1 : c.span();
				}
				count = Std.int(Math.max(count, n));
			}
			var tracks = [];
			for (c in cols)
				for (_ in 0...c.span())
					tracks.push(track(c.props.width));
			while (tracks.length < count)
				tracks.push(track(null));
			var template = tracks.length == 0 ? "none" : tracks.join(" ");
			for (r in rows)
				new Node(r).set(Prop.GridTemplateColumns, template);
		}
		// Rows come and go in the table and its sections, and cells in rows.
		ashui.layout.AfterChildren.watch(tree, "table " + haxe.Int64.toStr(id), parent -> within(tree, id, parent), layOut);
		layOut();
		return box;
	}

	/** A column's track: its width, or an equal share that may shrink below its content. **/
	static function track(width:Null<String>):String {
		if (width == null || StringTools.trim(width) == "")
			return "minmax(0, 1fr)";
		var w = StringTools.trim(width);
		if (StringTools.endsWith(w, "*"))
			return 'minmax(0, ${w.length == 1 ? "1" : w.substr(0, w.length - 1)}fr)';
		if (StringTools.endsWith(w, "%"))
			return w;
		return Std.parseFloat(w) + "px";
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

	function cell(tag:String):Element {
		var box = new Div({tag: tag, id: props.id}, children);
		ashui.text.InlineFlow.attach(box);
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
