package ashui.ui;

import ashui.input.Interaction;
import ashui.layout.Element;
import ashui.layout.LayoutTree;
import ashui.types.Brush;
import ashui.types.Style;

/** Where top-layer content goes: under a box on screen (a picker under its control), or centred. **/
enum Placement {
	/** Below the box at `(x, y)`, `width` by `height`, or above it when there is no room below; at least as wide, its content stretched to that. **/
	Below(x:Float, y:Float, width:Float, height:Float);

	Centered;
}

/** One entry of the top layer; `close` takes it out. **/
class TopEntry {
	public final content:Element;
	final layer:Div;
	final onClose:Null<Void->Void>;
	var closed = false;

	@:allow(ashui.ui.TopLayer)
	function new(content:Element, layer:Div, onClose:Null<Void->Void>) {
		this.content = content;
		this.layer = layer;
		this.onClose = onClose;
	}

	public function close():Void {
		if (closed)
			return;
		closed = true;
		@:privateAccess TopLayer.entries.remove(this);
		// The content is kept, to open again; only the layer around it goes.
		var parent = layer.tree.ancestors(content.node.id);
		if (parent.length > 0)
			layer.tree.detachChildren(parent[0]);
		layer.remove();
		if (onClose != null)
			onClose();
	}

	public var isOpen(get, never):Bool;

	inline function get_isOpen():Bool
		return !closed;
}

/**
	HTML's top layer: what draws above everything else in a tree, a
	select's list of options or a modal dialog. An entry is placed last
	under the tree's root, absolutely positioned in its coordinates, so it
	is drawn over the rest, hit first, and clipped by no element.

	Beneath its content is a backdrop as large as the root: transparent, or
	dimmed for a modal. A press on the backdrop, outside the content,
	closes the entry, as does Escape anywhere in it.
**/
class TopLayer {
	static final entries:Array<TopEntry> = [];

	/**
		Opens `content` in `tree`'s top layer, placed by `placement`.
		`backdrop` dims what is beneath; `onClose` runs however it closes.
	**/
	public static function open(tree:LayoutTree, content:Element, placement:Placement, ?backdrop:Brush, ?onClose:Void->Void):TopEntry {
		var root = tree.root;
		if (root == null)
			throw "TopLayer.open needs a tree that has been laid out";
		var rootBounds = tree.getBounds(root);
		var w = rootBounds == null ? 0.0 : rootBounds.width, h = rootBounds == null ? 0.0 : rootBounds.height;
		var shade = new Div({
			position: Absolute,
			left: 0,
			top: 0,
			width: w,
			height: h,
			bg: backdrop != null ? backdrop : Brush.solid(0, 0),
			alignItems: Align.Center,
			justifyContent: Justify.Center
		}, tree);
		var holder = switch placement {
			case Centered:
				new Div({}, [content], tree);
			case Below(x, y, bw, bh):
				// Below its box when it fits, else above it; never past the root's edges.
				var c = tree.getBounds(content.node);
				var ch = c == null ? 0.0 : c.height;
				var top = y + bh + ch <= h || y - ch < 0 ? y + bh : y - ch;
				// At least as wide as its box, the content stretched to it, as a select's list matches the select.
				new Div({
					position: Absolute,
					left: Math.max(0, Math.min(x, w - (c == null ? 0 : c.width))),
					top: top,
					minWidth: bw,
					flexDirection: FlexDirection.Column,
					alignItems: Align.Stretch
				}, [content], tree);
		}
		shade.appendChild(holder);
		var entry:Null<TopEntry> = null;
		Interaction.of(shade.node).onPointerDown(e -> {
			// A press on the backdrop itself, not on what it holds.
			if (e.target == shade.node && entry != null)
				entry.close();
		});
		Interaction.of(shade.node).onKeyDown(e -> switch e.key {
			case Named(Escape):
				e.preventDefault();
				if (entry != null)
					entry.close();
			case _:
		});
		tree.addChild(root.id, shade.node.id);
		entry = new TopEntry(content, shade, onClose);
		entries.push(entry);
		return entry;
	}

	/** The open entries, the topmost last. **/
	public static function openEntries():Array<TopEntry>
		return entries.copy();
}
