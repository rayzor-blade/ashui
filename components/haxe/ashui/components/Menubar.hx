package ashui.components;

import ashui.components.DropdownMenu;
import ashui.input.Interaction;
import ashui.layout.Element;
import ashui.ui.Component;

/**
	A row of application menus, such as File, Edit, and View.
	Each `MenubarMenu` contains a `MenubarTrigger` and `MenubarContent`
	with menu items. While a menu is open, hovering another trigger or
	pressing Left/Right switches menus. CSS: `.ui-menubar`,
	`.ui-menubar-trigger[data-state]`, and the dropdown menu classes.
**/
class Menubar extends Component<{?id:String}> {
	var menus:Array<MenubarMenu> = [];

	function render():Element {
		menus = [for (c in children) if (Std.isOfType(c, MenubarMenu)) (cast c : MenubarMenu)];
		for (m in menus)
			m.bar = this;
		return Library.part("ui-menubar", null, null, children, props.id);
	}

	/** Returns the currently open menu, or null. **/
	function openMenu():Null<MenubarMenu>
		return Lambda.find(menus, m -> m.opened.get());

	/** Closes the current menu and opens `next`. **/
	@:allow(ashui.components.MenubarMenu)
	function switchTo(next:MenubarMenu):Void {
		var current = openMenu();
		if (current == next)
			return;
		if (current != null)
			current.opened.set(false);
		next.opened.set(true);
	}

	/** Returns the adjacent menu in direction `dir`, wrapping at the ends. **/
	@:allow(ashui.components.MenubarMenu)
	function beside(from:MenubarMenu, dir:Int):MenubarMenu {
		var at = menus.indexOf(from);
		return menus[(at + dir + menus.length) % menus.length];
	}

	/** Finds the menu trigger under a pointer position while a menu is open. **/
	@:allow(ashui.components.MenubarMenu)
	function menuAt(x:Float, y:Float):Null<MenubarMenu> {
		for (m in menus) {
			var t = m.trigger;
			if (t == null)
				continue;
			var b = t.tree.getBounds(t.node);
			if (b != null && x >= b.x && x < b.x + b.width && y >= b.y && y < b.y + b.height)
				return m;
		}
		return null;
	}
}

/** One menu in a menubar. **/
class MenubarMenu extends DropdownMenu {
	@:allow(ashui.components.Menubar) var bar:Null<Menubar> = null;
	@:allow(ashui.components.Menubar) var trigger:Null<Element> = null;

	override function render():Element {
		for (c in children)
			if (Std.isOfType(c, MenubarTrigger))
				trigger = c;
		var el = super.render();
		// Its menu lines up with its trigger, as a menubar's do.
		if (floating != null)
			floating.align = "start";
		if (floating != null)
			floating.shown = entry -> entry.backdrop().onPointerMove(e -> {
				if (bar == null)
					return;
				var other = bar.menuAt(e.x, e.y);
				if (other != null && other != this)
					bar.switchTo(other);
			});
		return el;
	}

	override function sideKey(dir:Int):Bool {
		if (bar == null)
			return false;
		bar.switchTo(bar.beside(this, dir));
		return true;
	}
}

/** Text trigger highlighted while its menu is open. **/
class MenubarTrigger extends DropdownMenuTrigger {
	override function render():Element {
		var box = Library.part("ui-menubar-trigger", "button", null, children, props.id);
		ashui.css.Identity.of(box.tree, box.node.id).setAttribute("type", "button");
		var i = Interaction.of(box.node).setFocusable(true);
		i.onClick(_ -> {
			var m = DropdownMenu.registry.near(box.tree, box.node.id);
			if (m != null)
				m.opened.set(!m.opened.get());
		});
		return box;
	}
}

class MenubarContent extends DropdownMenuContent {}
class MenubarItem extends DropdownMenuItem {}
class MenubarLabel extends DropdownMenuLabel {}
class MenubarSeparator extends DropdownMenuSeparator {}
