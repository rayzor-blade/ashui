package ashui.components;

import ashui.components.Button;
import ashui.components.Dialog;
import ashui.input.Interaction;
import ashui.layout.Element;

/**
	An edge panel for settings or details, displayed over a frosted backdrop.

	Compose the dialog-style parts: `SheetTrigger`, `SheetContent`,
	`SheetHeader`, `SheetTitle`, `SheetDescription`, `SheetFooter`, and
	`SheetClose`. A corner close button, Escape, or a backdrop click dismisses
	the sheet. The footer occupies a band along the bottom.

	`Sm`, `Md` (default), and `Lg` allow widths of 320, 400, and 540 for side
	sheets, or heights of 200, 300, and 400 for top/bottom sheets. `Full` fills
	the window. CSS: `.ui-sheet` with `[data-side]`, `[data-size]`, `[open]`,
	and `[closing]`, plus `.ui-sheet-close` and the dialog content classes.
	Size variables: `--ui-sheet-width` and `--ui-sheet-height`.
**/
class Sheet extends Dialog {}

/** Button that opens its containing sheet. **/
class SheetTrigger extends DialogTrigger {}

/** Button that closes its containing sheet. **/
class SheetClose extends DialogClose {}

class SheetHeader extends DialogHeader {}
class SheetTitle extends DialogTitle {}
class SheetDescription extends DialogDescription {}
class SheetFooter extends DialogFooter {}

/** Sheet panel in the top layer. `side` selects the edge; a close button appears in the corner. **/
class SheetContent extends DialogContent {
	static var cross:Null<ashui.svg.SvgDocument> = null;

	function side():String
		return props.side == null ? "right" : props.side;

	override function panelClass():String
		return "ui-sheet";

	override function placement():ashui.ui.TopLayer.Placement
		return Edge(side());

	override function backdrop():ashui.types.Brush
		return ashui.types.Brush.blur(6, 0x000000, 0.4);

	override function contents():Array<Element> {
		if (cross == null)
			cross = ashui.svg.SvgDocument.of(<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M18 6 6 18"/><path d="m6 6 12 12"/></svg>);
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
