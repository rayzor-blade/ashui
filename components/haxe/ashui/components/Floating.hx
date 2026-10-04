package ashui.components;

import ashui.input.Focus;
import ashui.input.Interaction;
import ashui.layout.Element;
import ashui.layout.LayoutTree;
import ashui.reactive.Signal;
import ashui.reactive.Watch;
import ashui.ui.Div;
import ashui.ui.TopLayer;

/**
	A panel opened in the top layer beside an anchor while `open` is true: a
	popover's, a menu's. A press outside it or Escape closes it, setting
	`open` false; focus goes back to where it was. The panel is kept while
	closed, to open again as it was.
**/
class Floating {
	public final open:Signal<Bool>;
	final panel:Div;
	var anchor:Null<Element> = null;
	var side = "bottom";
	var gap = 4.0;
	var entry:Null<ashui.ui.TopEntry> = null;
	/** A point to open at instead of beside the anchor, as a context menu opens at the pointer. **/
	var point:Null<{x:Float, y:Float}> = null;
	/** Opened with no backdrop, the page beneath still under the pointer: a hover card. **/
	public var modeless = false;
	var before:Null<Interaction> = null;
	/** Called after it opens, to move focus into it; the panel takes focus when it is null. **/
	public var opened:Null<Void->Void> = null;

	public function new(open:Signal<Bool>, panel:Div) {
		this.open = open;
		this.panel = panel;
		new Watch(() -> open.get(), v -> if (v) show() else hide());
		ashui.reactive.Owner.onCleanup(hide);
	}

	/** Where it opens: `side` of `anchor` ("bottom", "top", "left" or "right"), `gap` from it. **/
	public function anchorTo(anchor:Element, side:String, gap:Float):Void {
		this.anchor = anchor;
		this.side = side;
		this.gap = gap;
		if (open.get())
			show();
	}

	/** Opens it with its top-left at `(x, y)` in the tree's coordinates. **/
	public function openAt(x:Float, y:Float):Void {
		if (entry != null)
			entry.close();
		point = {x: x, y: y};
		if (open.get())
			show();
		else
			open.set(true);
	}

	function show():Void {
		if (entry != null || anchor == null)
			return;
		var tree = anchor.tree;
		var b = tree.root == null ? null : tree.getBounds(anchor.node);
		if (b == null) {
			// Not laid out yet: opened at the next flush.
			var retry:Null<LayoutTree->Void> = null;
			retry = t -> if (t == tree && tree.root != null) {
				LayoutTree.flushHooks.remove(retry);
				if (open.get())
					show();
			};
			LayoutTree.flushHooks.push(retry);
			return;
		}
		before = Focus.of(tree);
		var placement:ashui.ui.TopLayer.Placement = point != null ? At(point.x, point.y) : Beside(b.x, b.y, b.width, b.height, side, gap);
		point = null;
		entry = TopLayer.open(tree, panel, placement, null, () -> {
			entry = null;
			if (open.get())
				open.set(false);
			if (before != null && !modeless)
				Focus.set(before, Focus.byKeyboard);
		}, false, true, modeless);
		// Focus into it, so its keys and Escape reach it: what `opened` says, or the panel itself. A modeless one leaves focus where it is.
		if (opened != null)
			opened();
		else if (!modeless)
			Focus.set(Interaction.of(panel.node).setFocusable(true), false);
	}

	function hide():Void
		if (entry != null)
			entry.close();
}
