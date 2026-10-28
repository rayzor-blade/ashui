package ashui.components;

import ashui.components.DropdownMenu;
import ashui.input.Interaction;
import ashui.layout.Element;
import ashui.ui.Component;

/**
	A menu opened at the pointer by a right-click on `ContextMenuTrigger`,
	or by the context-menu key while the trigger has focus.
	`ContextMenuContent`, `ContextMenuItem`, `ContextMenuLabel`, and
	`ContextMenuSeparator` share dropdown menu behavior and keyboard controls.
	CSS: `.ui-context-menu-trigger` and the dropdown menu classes.
**/
class ContextMenu extends DropdownMenu {}

/** Area that opens a context menu on right-click. Children supply the visible content. **/
class ContextMenuTrigger extends Component<{?id:String}> {
	function render():Element {
		var area = Library.part("ui-context-menu-trigger", null, null, children, props.id);
		var i = Interaction.of(area.node).setFocusable(true);
		i.onPointerDown(e -> if (e.button != null && e.button.match(Right)) {
			e.preventDefault();
			var m = DropdownMenu.registry.near(area.tree, area.node.id);
			if (m != null)
				m.openAt(e.x, e.y);
		});
		i.onKeyDown(e -> switch e.key {
			case Named(ContextMenu):
				var b = area.tree.getBounds(area.node);
				var m = DropdownMenu.registry.near(area.tree, area.node.id);
				if (m != null && b != null) {
					e.preventDefault();
					m.openAt(b.x + 8, b.y + 8);
				}
			case _:
		});
		return area;
	}
}

class ContextMenuContent extends DropdownMenuContent {}
class ContextMenuItem extends DropdownMenuItem {}
class ContextMenuLabel extends DropdownMenuLabel {}
class ContextMenuSeparator extends DropdownMenuSeparator {}
