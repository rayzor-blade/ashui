package ashui.ui;

import ashui.css.Identity;
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

	/**
		On `side` of the box at `(x, y)`, `width` by `height` ("top", "bottom",
		"left" or "right"), `gap` from it and centred along it, as wide as its
		content; on the opposite side when there is no room, and never past
		the root's edges. A tooltip's place.
	**/
	Beside(x:Float, y:Float, width:Float, height:Float, side:String, gap:Float);
}

/** One entry of the top layer; `close` takes it out. **/
class TopEntry {
	public final content:Element;
	final layer:Div;
	final holder:Div;
	final onClose:Null<Void->Void>;
	var closed = false;

	@:allow(ashui.ui.TopLayer)
	function new(content:Element, layer:Div, holder:Div, onClose:Null<Void->Void>) {
		this.content = content;
		this.layer = layer;
		this.holder = holder;
		this.onClose = onClose;
	}

	public function close():Void {
		if (closed)
			return;
		closed = true;
		@:privateAccess TopLayer.entries.remove(this);
		// Marked closing, so CSS animates it away, and taken out once that has played.
		var tree = layer.tree;
		var marked = [Identity.of(tree, layer.node.id), Identity.of(tree, content.node.id)];
		for (identity in marked)
			if (identity != null)
				identity.setAttribute("closing", "");
		var theme = ashui.theme.ThemeState.tryGet();
		var seconds = theme == null ? 0 : theme.animations().durationFaster / 1000;
		// While it goes, presses pass through it to what is beneath.
		tree.setPassThrough(layer.node.id, true);
		var layerNode = layer.node.id, holderNode = holder.node.id;
		function finish() {
			for (identity in marked)
				if (identity != null)
					identity.setAttribute("closing", null);
			tree.setPassThrough(layerNode, false);
			// The content is kept, to open again; only the layer around it goes. Opened again meanwhile, it is in another layer by now.
			if (content.node != null) {
				var parent = tree.ancestors(content.node.id);
				if (parent.length > 0 && parent[0] == holderNode)
					tree.detachChildren(holderNode);
			}
			if (layer.node != null)
				layer.remove();
		}
		if (seconds > 0)
			ashui.animation.AnimationScheduler.main.after(seconds, finish);
		else
			finish();
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
	public static function open(tree:LayoutTree, content:Element, placement:Placement, ?backdrop:Brush, ?onClose:Void->Void, passThrough = false):TopEntry {
		var root = tree.root;
		if (root == null)
			throw "TopLayer.open needs a tree that has been laid out";
		var rootBounds = tree.getBounds(root);
		var w = rootBounds == null ? 0.0 : rootBounds.width, h = rootBounds == null ? 0.0 : rootBounds.height;
		var shade = new Div({
			tag: "backdrop",
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
			case Beside(x, y, bw, bh, side, gap):
				var c = tree.getBounds(content.node);
				var cw = c == null ? 0.0 : c.width, ch = c == null ? 0.0 : c.height;
				var s = side;
				// The opposite side when this one has no room.
				if (s == "top" && y - gap - ch < 0)
					s = "bottom";
				else if (s == "bottom" && y + bh + gap + ch > h)
					s = "top";
				else if (s == "left" && x - gap - cw < 0)
					s = "right";
				else if (s == "right" && x + bw + gap + cw > w)
					s = "left";
				var left = switch s {
					case "left": x - gap - cw;
					case "right": x + bw + gap;
					case _: x + (bw - cw) / 2;
				}
				var top = switch s {
					case "top": y - gap - ch;
					case "bottom": y + bh + gap;
					case _: y + (bh - ch) / 2;
				}
				var holder = new Div({position: Absolute, left: Math.max(0, Math.min(left, w - cw)), top: Math.max(0, Math.min(top, h - ch))}, [content], tree);
				ashui.css.Identity.of(tree, content.node.id).setAttribute("data-side", s);
				holder;
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
		// What only shows, as a tooltip, takes no presses: they reach what is beneath.
		if (passThrough)
			tree.setPassThrough(shade.node.id, true);
		entry = new TopEntry(content, shade, holder, onClose);
		entries.push(entry);
		return entry;
	}

	/** The open entries, the topmost last. **/
	public static function openEntries():Array<TopEntry>
		return entries.copy();
}
