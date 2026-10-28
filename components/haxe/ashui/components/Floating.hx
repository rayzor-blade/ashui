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
	Positions a retained popup beside an anchor while its open signal is true.
	Outside clicks and Escape close the popup, update the signal, and restore
	previous focus. Closing preserves the panel for the next opening.
**/
class Floating {
	public final open:Signal<Bool>;
	final panel:Element;
	var anchor:Null<Element> = null;
	var side = "bottom";
	var gap = 4.0;
	/** Anchor alignment: `start` or `end`, rather than the default centered placement. **/
	public var align:Null<String> = null;
	var entry:Null<ashui.ui.TopEntry> = null;
	/** Explicit opening point for menus positioned at the pointer. **/
	var point:Null<{x:Float, y:Float}> = null;
	/** Omits the backdrop so the page remains interactive, as for a hover card. **/
	public var modeless = false;
	/** Receives the top-layer entry each time the popup opens. **/
	public var shown:Null<ashui.ui.TopEntry->Void> = null;
	var before:Null<Interaction> = null;
	/** Moves focus after opening. When absent, the panel receives focus. **/
	public var opened:Null<Void->Void> = null;

	public function new(open:Signal<Bool>, panel:Element) {
		this.open = open;
		this.panel = panel;
		new Watch(() -> open.get(), v -> if (v) show() else hide());
		ashui.reactive.Owner.onCleanup(hide);
	}

	/** Anchors the popup to `bottom`, `top`, `left`, or `right` with the given gap. **/
	public function anchorTo(anchor:Element, side:String, gap:Float):Void {
		this.anchor = anchor;
		this.side = side;
		this.gap = gap;
		if (open.get())
			show();
	}

	/** Opens with the panel top-left at `(x, y)` in tree coordinates. **/
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
		var b = tree.root == null ? null : tree.getScrolledBounds(anchor.node);
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
		// Focus goes back to its own trigger when it closes, else to what had it: a menubar's menus open one from another.
		var own = Interaction.find(anchor.node);
		before = own != null && own.focusable ? own : Focus.of(tree);
		var placement:ashui.ui.TopLayer.Placement = point != null ? At(point.x, point.y) : Beside(b.x, b.y, b.width, b.height, side, gap, align);
		point = null;
		entry = TopLayer.open(tree, panel, placement, null, () -> {
			entry = null;
			if (open.get())
				open.set(false);
			if (before != null && !modeless)
				Focus.set(before, Focus.byKeyboard);
		}, false, true, modeless);
		if (shown != null)
			shown(entry);
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
