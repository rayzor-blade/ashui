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
		entry = TopLayer.open(tree, panel, Beside(b.x, b.y, b.width, b.height, side, gap), null, () -> {
			entry = null;
			if (open.get())
				open.set(false);
			if (before != null)
				Focus.set(before, Focus.byKeyboard);
		});
		// Focus into it, so its keys and Escape reach it: what `opened` says, or the panel itself.
		if (opened != null)
			opened();
		else
			Focus.set(Interaction.of(panel.node).setFocusable(true), false);
	}

	function hide():Void
		if (entry != null)
			entry.close();
}
