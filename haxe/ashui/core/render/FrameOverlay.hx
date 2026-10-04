package ashui.core.render;

import ashui.layout.Element;
import ashui.layout.LayoutTree;
import ashui.layout.Node;

/**
	Something drawn over every frame after the UI is, such as a debugger's
	motion trails: added to `Offscreen.overlays`, it is called with the tree
	just drawn and builds what it draws in a tree of its own, so the UI's
	tree, styles and hit testing never see it. `paint` lays an element out
	at the frame's size and draws it over the frame.
**/
interface FrameOverlay {
	function draw(tree:LayoutTree, root:Node, width:Int, height:Int, paint:Element->Void):Void;
}
