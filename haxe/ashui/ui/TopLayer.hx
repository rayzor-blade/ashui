package ashui.ui;

import ashui.css.Identity;
import ashui.input.Interaction;
import ashui.layout.Element;
import ashui.layout.LayoutTree;
import ashui.types.Brush;
import ashui.types.Style;

/** Placement of content above the page, such as dialogs, menus, and pickers. **/
enum Placement {
	/** Places content below the anchor rectangle, or above when space is limited. Stretches content to at least the anchor width. **/
	Below(x:Float, y:Float, width:Float, height:Float);

	Centered;

	/**
		Places content beside an anchor rectangle with the given gap.
		`side` is `top`, `bottom`, `left`, or `right`; placement flips when needed
		and stays within root bounds. Content is centered along the anchor unless
		`align` is `start` or `end`.
	**/
	Beside(x:Float, y:Float, width:Float, height:Float, side:String, gap:Float, ?align:String);

	/** Stretches content along the root edge: `left`, `right`, `top`, or `bottom`. Used by sheets. **/
	Edge(side:String);

	/** Places the content top-left at `(x, y)`, flipping left or upward to stay within root bounds. Used by context menus. **/
	At(x:Float, y:Float);
}

/** User action requesting dismissal of a top-layer entry. **/
enum DismissReason {
	Escape;
	Backdrop;
}

/** An open top-layer entry. Call `close()` to remove it. **/
class TopEntry {
	public final content:Element;

	final layer:Div;
	final dim:Div;
	final holder:Div;
	final onClose:Null<Void->Void>;
	final placement:Placement;
	var closed = false;

	/** Closed entries waiting for exit animations before their layers can be removed. **/
	static final leaving:Array<TopEntry> = [];

	/** Whether another entry has reopened the content and taken responsibility for cleanup. **/
	var reclaimed = false;

	/**
		Reopens content while its previous entry is still animating out.
		Detaches the content from the old holder to prevent later cleanup from
		removing the reopened content. The old backdrop continues fading.
	**/
	@:allow(ashui.ui.TopLayer)
	static function reclaim(content:Element):Void {
		if (content.node == null)
			return;
		for (entry in leaving.copy()) {
			if (entry.content != content || entry.holder.node == null)
				continue;
			var tree = entry.layer.tree;
			var parent = tree.ancestors(content.node.id);
			if (parent.length > 0 && parent[0] == entry.holder.node.id)
				tree.detachChildren(entry.holder.node.id);
			var identity = Identity.of(tree, content.node.id);
			if (identity != null)
				identity.setAttribute("closing", null);
			entry.reclaimed = true;
		}
	}

	/** Last holder position, used to avoid redundant placement updates. **/
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
		Repositions anchored content for its current size. Flips and clamps
		placement to fit the root. Returns true when another layout pass is
		needed; centered content is positioned by layout.
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

	public function close():Void {
		if (closed)
			return;
		closed = true;
		@:privateAccess TopLayer.entries.remove(this);
		// Marked closing, so CSS animates it away, and taken out once that has played.
		var tree = layer.tree;
		// Owner teardown can remove the content before closing its top-layer entry.
		if (content.node == null || layer.node == null || holder.node == null || dim.node == null) {
			if (content.node != null && holder.node != null) {
				var parent = tree.ancestors(content.node.id);
				if (parent.length > 0 && parent[0] == holder.node.id)
					tree.detachChildren(holder.node.id);
			}
			if (layer.node != null)
				layer.remove();
			if (onClose != null)
				onClose();
			return;
		}
		var marked = [Identity.of(tree, dim.node.id), Identity.of(tree, content.node.id)];
		for (identity in marked)
			if (identity != null)
				identity.setAttribute("closing", "");
		var theme = ashui.theme.ThemeState.tryGet();
		var seconds = theme == null ? 0 : theme.animations().durationFaster / 1000;
		// While it goes, presses pass through it to what is beneath.
		tree.setPassThrough(layer.node.id, true);
		var layerNode = layer.node.id, holderNode = holder.node.id;
		leaving.push(this);
		function finish() {
			leaving.remove(this);
			for (identity in marked)
				if (identity != null && !(reclaimed && identity == marked[1]))
					identity.setAttribute("closing", null);
			tree.setPassThrough(layerNode, false);
			// The content is kept, to open again; only the layer around it goes. Opened again meanwhile, it was taken out of this one.
			if (!reclaimed && content.node != null) {
				var parent = tree.ancestors(content.node.id);
				if (parent.length > 0 && parent[0] == holderNode)
					tree.detachChildren(holderNode);
			}
			if (layer.node != null)
				layer.remove();
		}
		// Taken out once its closing animations have played, the backdrop's and the content's, however long they run.
		ashui.css.Animations.whenPlayed(marked, seconds, finish);
		if (onClose != null)
			onClose();
	}

	/** Returns the backdrop interaction, for example to switch menubar menus on hover. **/
	public function backdrop():Interaction
		return Interaction.of(layer.node);

	public var isOpen(get, never):Bool;

	inline function get_isOpen():Bool
		return !closed;
}

/**
	Displays overlays above the rest of a layout tree.

	Entries attach to the root and use root coordinates. They draw last,
	receive hit tests first, and bypass ancestor clipping. A root-sized
	backdrop can block or dim the page; backdrop clicks and Escape dismiss
	entries unless configured otherwise.
**/
class TopLayer {
	static final entries:Array<TopEntry> = [];
	static var hooked = false;

	/** Repositions anchored entries after layout changes their content size, before painting. **/
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
		Opens content in the tree top layer at the requested placement.

		`backdrop` dims the page; `onClose` runs whenever the entry closes.
		Set `dismissible` to false to ignore Escape and backdrop clicks.
		Set `modeless` to true to omit the backdrop and keep the page interactive.
		When supplied, `onDismiss` handles user dismissal requests instead of
		closing the entry directly.
	**/
	public static function open(tree:LayoutTree, content:Element, placement:Placement, ?backdrop:Brush, ?onClose:Void->Void, passThrough = false,
			dismissible = true, modeless = false, ?onDismiss:DismissReason->Void):TopEntry {
		var root = tree.root;
		if (root == null)
			throw "TopLayer.open needs a tree that has been laid out";
		var rootBounds = tree.getBounds(root);
		var w = rootBounds == null ? 0.0 : rootBounds.width,
			h = rootBounds == null ? 0.0 : rootBounds.height;
		TopEntry.reclaim(content);
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
				new Div({
					position: Absolute,
					minWidth: bw,
					flexDirection: FlexDirection.Column,
					alignItems: Align.Stretch
				}, [content], tree);
			case Beside(_, _, _, _, _, _, _) | At(_, _):
				new Div({position: Absolute}, [content], tree);
			case Edge(side):
				// Pinned to its edge and stretched along it; the content stretches with it.
				var holder = new Div({
					position: Absolute,
					flexDirection: side == "left" || side == "right" ? FlexDirection.Row : FlexDirection.Column,
					alignItems: Align.Stretch
				}, [content], tree);
				var n = holder.node;
				switch side {
					case "left":
						n.set(ashui.layout.Prop.Left, 0);
						n.set(ashui.layout.Prop.Top, 0);
						n.set(ashui.layout.Prop.Bottom, 0);
					case "top":
						n.set(ashui.layout.Prop.Left, 0);
						n.set(ashui.layout.Prop.Right, 0);
						n.set(ashui.layout.Prop.Top, 0);
					case "bottom":
						n.set(ashui.layout.Prop.Left, 0);
						n.set(ashui.layout.Prop.Right, 0);
						n.set(ashui.layout.Prop.Bottom, 0);
					case _:
						n.set(ashui.layout.Prop.Right, 0);
						n.set(ashui.layout.Prop.Top, 0);
						n.set(ashui.layout.Prop.Bottom, 0);
				}
				holder;
		}
		shade.appendChild(holder);
		var entry:Null<TopEntry> = null;
		Interaction.of(shade.node).onPointerDown(e -> {
			// A press on the backdrop itself, not on what it holds.
			if (!e.defaultPrevented && (e.target == shade.node || e.target == dim.node) && entry != null && dismissible) {
				if (onDismiss != null)
					onDismiss(Backdrop)
				else
					entry.close();
			}
		});
		Interaction.of(shade.node).onKeyDown(e -> switch e.key {
			case Named(Escape):
				if (e.defaultPrevented)
					return;
				e.preventDefault();
				if (entry != null && dismissible) {
					if (onDismiss != null)
						onDismiss(Escape)
					else
						entry.close();
				}
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

	/** Returns open entries in stacking order, with the topmost entry last. **/
	public static function openEntries():Array<TopEntry>
		return entries.copy();
}
