package ashui.components;

import ashui.components.Button;
import ashui.components.Dialog;
import ashui.input.Interaction;
import ashui.layout.Element;

/**
	A sheet: a dialog that slides in from an edge of the window, its inner
	corners rounded, for settings or details beside the page. Its parts are
	the dialog's: a `SheetTrigger`, a `SheetContent` holding a
	`SheetHeader` (`SheetTitle`, `SheetDescription`), what it shows and a
	`SheetFooter`; a close button sits in its corner, and `SheetClose`
	closes it too. Escape or a press on the page behind closes it. CSS:
	`.ui-sheet` (`[data-side]`, `[data-size]`, `[open]`, `[closing]`),
	`.ui-sheet-close`, and the dialog's header, title, description and
	footer classes inside it; `--ui-sheet-width`, `-height`. Its sizes are
	the dialog's: `Sm`, `Md` (the default), `Lg` reach 320, 400 and 540
	across from the left or right, 200, 300 and 400 from the top or bottom;
	`Full`, the whole window.
**/
class Sheet extends Dialog {}

/** A button that opens the sheet it is in. **/
class SheetTrigger extends DialogTrigger {}

/** A button that closes the sheet it is in. **/
class SheetClose extends DialogClose {}

class SheetHeader extends DialogHeader {}
class SheetTitle extends DialogTitle {}
class SheetDescription extends DialogDescription {}
class SheetFooter extends DialogFooter {}

/** The sheet's panel, along its edge in the top layer while open: a dialog panel, its `side` the edge, a close button in its corner. **/
class SheetContent extends DialogContent {
	static var cross:Null<ashui.svg.SvgDocument> = null;

	function side():String
		return props.side == null ? "right" : props.side;

	override function panelClass():String
		return "ui-sheet";

	override function placement():ashui.ui.TopLayer.Placement
		return Edge(side());

	override function contents():Array<Element> {
		if (cross == null)
			cross = ashui.svg.SvgDocument.parse('<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M18 6 6 18"/><path d="m6 6 12 12"/></svg>');
		var icon = new ashui.ui.Svg(cross, {width: 18, height: 18});
		var close = Library.part("ui-sheet-close", "button", null, [icon]);
		ashui.css.Identity.of(close.tree, close.node.id).setAttribute("type", "button");
		Interaction.of(close.node).setFocusable(true).onClick(_ -> {
			var d = Dialog.near(close.tree, close.node.id);
			if (d != null)
				d.opened.set(false);
		});
		return children.concat([close]);
	}

	override function render():Element {
		var el = super.render();
		ashui.css.Identity.of(panel.tree, panel.node.id).setAttribute("data-side", side());
		return el;
	}
}
