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
		the root's edges. A tooltip's place. `align` "start" or "end" lines it
		up with that end of the box instead of centring it, as a menubar's
		menus line up with their triggers.
	**/
	Beside(x:Float, y:Float, width:Float, height:Float, side:String, gap:Float, ?align:String);

	/** Along one edge of the root, "left", "right", "top" or "bottom", stretched along it: a sheet's place. **/
	Edge(side:String);

	/** Its top-left at `(x, y)`, or flipped left and up of it where it would run past the root's edges: a context menu at the pointer. **/
	At(x:Float, y:Float);
}

/** One entry of the top layer; `close` takes it out. **/
class TopEntry {
	public final content:Element;
	final layer:Div;
	final dim:Div;
	final holder:Div;
	final onClose:Null<Void->Void>;
	final placement:Placement;
	var closed = false;
	/** Where the holder was last put, so placing it again only moves it when the content's size moved it. **/
	var placed:Null<{left:Float, top:Float}> = null;

	@:allow(ashui.ui.TopLayer)
	function new(content:Element, layer:Div, dim:Div, holder:Div, onClose:Null<Void->Void>, placement:Placement) {
		this.content = content;
		this.layer = layer;
		this.dim = dim;
		this.holder = holder;
		this.onClose = onClose;
		this.placement = placement;
	}

	/**
		Puts an anchored entry where its placement says for the content's
		size now: under or beside its box, flipped to the other side when
		there is no room, never past the root's edges. True when that moved
		it, for another layout pass. A centred entry is placed by layout.
	**/
	@:allow(ashui.ui.TopLayer)
	function place():Bool {
		if (closed || content.node == null || holder.node == null)
			return false;
		var tree = layer.tree;
		var root = tree.root;
		var rb = root == null ? null : tree.getBounds(root);
		var w = rb == null ? 0.0 : rb.width, h = rb == null ? 0.0 : rb.height;
		var c = tree.getBounds(content.node);
		var cw = c == null ? 0.0 : c.width, ch = c == null ? 0.0 : c.height;
		var spot:Null<{left:Float, top:Float}> = switch placement {
			case Centered | Edge(_):
				null;
			case At(x, y):
				{left: x + cw <= w ? x : Math.max(0, x - cw), top: y + ch <= h ? y : Math.max(0, y - ch)};
			case Below(x, y, bw, bh):
				// Below its box when it fits, else above it.
				var top = y + bh + ch <= h || y - ch < 0 ? y + bh : y - ch;
				{left: Math.max(0, Math.min(x, w - cw)), top: top};
			case Beside(x, y, bw, bh, side, gap, align):
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
					case _: align == "start" ? x : align == "end" ? x + bw - cw : x + (bw - cw) / 2;
				}
				var top = switch s {
					case "top": y - gap - ch;
					case "bottom": y + bh + gap;
					case _: align == "start" ? y : align == "end" ? y + bh - ch : y + (bh - ch) / 2;
				}
				var identity = Identity.of(tree, content.node.id);
				if (identity != null && identity.attribute("data-side") != s)
					identity.setAttribute("data-side", s);
				{left: Math.max(0, Math.min(left, w - cw)), top: Math.max(0, Math.min(top, h - ch))};
		}
		if (spot == null || (placed != null && Math.abs(placed.left - spot.left) < 0.5 && Math.abs(placed.top - spot.top) < 0.5))
			return false;
		placed = spot;
		holder.node.set(ashui.layout.Prop.Left, spot.left);
		holder.node.set(ashui.layout.Prop.Top, spot.top);
		return true;
	}

	/** The longest a closing entry waits for its animations, in seconds. **/
	static inline var CLOSE_LIMIT = 2.0;

	public function close():Void {
		if (closed)
			return;
		closed = true;
		@:privateAccess TopLayer.entries.remove(this);
		// Marked closing, so CSS animates it away, and taken out once that has played.
		var tree = layer.tree;
		var marked = [Identity.of(tree, dim.node.id), Identity.of(tree, content.node.id)];
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
		if (seconds > 0) {
			// Taken out once its closing animations have played, the backdrop's and the content's, however long they run:
			// the restyle that starts them comes within `seconds`, and none runs past the limit.
			var waited = 0.0;
			ashui.animation.AnimationScheduler.main.addTicker(dt -> {
				waited += dt;
				// Left after this tick, whether the animations' tickers run before this one or after.
				var left = 0.0;
				for (identity in marked)
					if (identity != null)
						left = Math.max(left, ashui.css.Animations.remaining(identity) - dt);
				if (waited < CLOSE_LIMIT && (waited < seconds || left > 0))
					return true;
				finish();
				return false;
			});
		} else
			finish();
		if (onClose != null)
			onClose();
	}

	/** The backdrop's interaction: what the pointer does over the page while it is open, a menubar watching for another of its menus. **/
	public function backdrop():Interaction
		return Interaction.of(layer.node);

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
	static var hooked = false;

	/** Anchored entries are placed again after each layout pass that changed their content's size, before the frame is drawn. **/
	static function hook():Void {
		if (hooked)
			return;
		hooked = true;
		LayoutTree.layoutHooks.push(tree -> {
			var moved = false;
			for (e in entries)
				if (@:privateAccess e.layer.tree == tree && @:privateAccess e.place())
					moved = true;
			moved;
		});
	}

	/**
		Opens `content` in `tree`'s top layer, placed by `placement`.
		`backdrop` dims what is beneath; `onClose` runs however it closes.
		Not `dismissible`, a press on the backdrop or Escape leaves it open:
		only its own controls close it, as an alert dialog's. `modeless`, it
		has no backdrop at all: the page beneath takes presses and the pointer
		as before while the content takes its own, as a hover card's.
	**/
	public static function open(tree:LayoutTree, content:Element, placement:Placement, ?backdrop:Brush, ?onClose:Void->Void, passThrough = false,
			dismissible = true, modeless = false):TopEntry {
		var root = tree.root;
		if (root == null)
			throw "TopLayer.open needs a tree that has been laid out";
		var rootBounds = tree.getBounds(root);
		var w = rootBounds == null ? 0.0 : rootBounds.width, h = rootBounds == null ? 0.0 : rootBounds.height;
		var shade = new Div({
			position: Absolute,
			left: 0,
			top: 0,
			// Modeless, of no size: what it holds is hit where it is, and nothing else of it is there.
			width: modeless ? 0 : w,
			height: modeless ? 0 : h,
			alignItems: Align.Center,
			justifyContent: Justify.Center
		}, tree);
		// The backdrop beside the content, under it, as HTML's `::backdrop`: it fades on its own, and what the content does is its own.
		var dim = new Div({
			tag: "backdrop",
			position: Absolute,
			left: 0,
			top: 0,
			width: modeless ? 0 : w,
			height: modeless ? 0 : h,
			bg: backdrop != null && !modeless ? backdrop : Brush.solid(0, 0)
		}, tree);
		shade.appendChild(dim);
		var holder = switch placement {
			case Centered:
				new Div({}, [content], tree);
			case Below(_, _, bw, _):
				// At least as wide as its box, the content stretched to it, as a select's list matches the select.
				new Div({position: Absolute, minWidth: bw, flexDirection: FlexDirection.Column, alignItems: Align.Stretch}, [content], tree);
			case Beside(_, _, _, _, _, _, _) | At(_, _):
				new Div({position: Absolute}, [content], tree);
			case Edge(side):
				// Pinned to its edge and stretched along it; the content stretches with it.
				var holder = new Div({position: Absolute, flexDirection: side == "left" || side == "right" ? FlexDirection.Row : FlexDirection.Column,
					alignItems: Align.Stretch}, [content], tree);
				var n = holder.node;
				switch side {
					case "left": n.set(ashui.layout.Prop.Left, 0); n.set(ashui.layout.Prop.Top, 0); n.set(ashui.layout.Prop.Bottom, 0);
					case "top": n.set(ashui.layout.Prop.Left, 0); n.set(ashui.layout.Prop.Right, 0); n.set(ashui.layout.Prop.Top, 0);
					case "bottom": n.set(ashui.layout.Prop.Left, 0); n.set(ashui.layout.Prop.Right, 0); n.set(ashui.layout.Prop.Bottom, 0);
					case _: n.set(ashui.layout.Prop.Right, 0); n.set(ashui.layout.Prop.Top, 0); n.set(ashui.layout.Prop.Bottom, 0);
				}
				holder;
		}
		shade.appendChild(holder);
		var entry:Null<TopEntry> = null;
		Interaction.of(shade.node).onPointerDown(e -> {
			// A press on the backdrop itself, not on what it holds.
			if ((e.target == shade.node || e.target == dim.node) && entry != null && dismissible)
				entry.close();
		});
		Interaction.of(shade.node).onKeyDown(e -> switch e.key {
			case Named(Escape):
				e.preventDefault();
				if (entry != null && dismissible)
					entry.close();
			case _:
		});
		tree.addChild(root.id, shade.node.id);
		// What only shows, as a tooltip, takes no presses: they reach what is beneath.
		if (passThrough)
			tree.setPassThrough(shade.node.id, true);
		entry = new TopEntry(content, shade, dim, holder, onClose, placement);
		entries.push(entry);
		// Placed now for what size the content has, and again once layout gives it one.
		hook();
		entry.place();
		return entry;
	}

	/** The open entries, the topmost last. **/
	public static function openEntries():Array<TopEntry>
		return entries.copy();
}
