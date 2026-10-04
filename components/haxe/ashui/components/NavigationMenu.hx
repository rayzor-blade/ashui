package ashui.components;

import ashui.input.Interaction;
import ashui.layout.Element;
import ashui.reactive.Signal;
import ashui.state.Machine;
import ashui.ui.Component;
import ashui.ui.Div;

/**
	A site's navigation: a row of `NavigationMenuLink`s and
	`NavigationMenuItem`s, each item a `NavigationMenuTrigger` whose
	`NavigationMenuContent` opens under it while the pointer rests on it or
	it is pressed, one at a time; moving to another item opens that one in
	its place. CSS: `.ui-nav-menu`, `.ui-nav-link` (`[data-active]`),
	`.ui-nav-trigger` (`[data-state]`), `.ui-nav-content`.
**/
class NavigationMenu extends Component<{?id:String}> {
	var items:Array<NavigationMenuItem> = [];

	function render():Element {
		items = [for (c in children) if (Std.isOfType(c, NavigationMenuItem)) (cast c : NavigationMenuItem)];
		for (i in items)
			i.menu = this;
		return Library.part("ui-nav-menu", "nav", null, children, props.id);
	}

	/** Closes every item but `open`, when it opens. **/
	@:allow(ashui.components.NavigationMenuItem)
	function opened(open:NavigationMenuItem):Void
		for (i in items)
			if (i != open)
				i.close();
}

/** Where a navigation item is: closed, waiting to open, open, or waiting to close. **/
private enum NavState {
	Closed;
	Waiting;
	Open;
	Leaving;
}

private enum NavEvent {
	Enter;
	Leave;
	Press;
	Timeout;
	Close;
}

/** One of the menu's items with a panel: its trigger and its content. **/
class NavigationMenuItem extends Component<{?id:String}> {
	@:allow(ashui.components.NavigationMenu) var menu:Null<NavigationMenu> = null;
	var machine:Null<Machine<NavState, NavEvent>> = null;

	function render():Element {
		var m = new Machine<NavState, NavEvent>(Closed, (s, e) -> switch [s, e] {
			case [Closed, Enter]: Waiting;
			case [Closed, Press] | [Waiting, Press] | [Waiting, Timeout] | [Leaving, Enter]: Open;
			case [Waiting, Leave]: Closed;
			case [Open, Press]: Closed;
			case [Open, Leave]: Leaving;
			case [Leaving, Timeout]: Closed;
			case [_, Close]: Closed;
			case _: null;
		});
		machine = m;
		m.after(Waiting, 0.15, Timeout);
		m.after(Leaving, 0.2, Timeout);
		var open = Signal.make(false);
		m.onEnter(Open, _ -> {
			open.set(true);
			if (menu != null)
				menu.opened(this);
		});
		m.onEnter(Closed, _ -> open.set(false));
		var trigger:Null<NavigationMenuTrigger> = null, content:Null<NavigationMenuContent> = null;
		for (c in children)
			if (Std.isOfType(c, NavigationMenuTrigger))
				trigger = cast c;
			else if (Std.isOfType(c, NavigationMenuContent))
				content = cast c;
		if (trigger != null) {
			ashui.css.Identity.of(trigger.tree, trigger.node.id).bindAttribute("data-state", m.name());
			var ti = Interaction.of(trigger.node);
			ti.onPointerEnter(_ -> m.send(Enter));
			ti.onPointerLeave(_ -> m.send(Leave));
			ti.onClick(_ -> m.send(Press));
		}
		if (content != null) {
			var panel = content.panel;
			ashui.css.Identity.of(panel.tree, panel.node.id).bindAttribute("data-state", m.name());
			var ci = Interaction.of(panel.node);
			ci.onPointerEnter(_ -> m.send(Enter));
			ci.onPointerLeave(_ -> m.send(Leave));
			var floating = new Floating(open, panel);
			floating.modeless = true;
			floating.align = "start";
			if (trigger != null)
				floating.anchorTo(trigger, "bottom", 6);
		}
		return Library.part("ui-nav-item", null, null, children, props.id);
	}

	@:allow(ashui.components.NavigationMenu)
	function close():Void
		if (machine != null)
			machine.send(Close);
}

/** An item's trigger: its label and a chevron that turns while its panel is open. **/
class NavigationMenuTrigger extends Component<{?id:String}> {
	static var chevron:Null<ashui.svg.SvgDocument> = null;

	function render():Element {
		if (chevron == null)
			chevron = ashui.svg.SvgDocument.parse('<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M6 9l6 6 6-6"/></svg>');
		var icon = new ashui.ui.Svg(chevron, {width: 12, height: 12});
		ashui.css.Identity.of(icon.tree, icon.node.id).setClasses(["ui-nav-chevron"]);
		var box = Library.part("ui-nav-trigger", "button", null, children.concat([icon]), props.id);
		ashui.css.Identity.of(box.tree, box.node.id).setAttribute("type", "button");
		Interaction.of(box.node).setFocusable(true);
		return box;
	}
}

/** An item's panel: kept while closed, under its trigger in the top layer while open. **/
class NavigationMenuContent extends Component<{?id:String}> {
	@:allow(ashui.components.NavigationMenuItem)
	var panel(default, null):Div;

	function render():Element {
		panel = Library.part("ui-nav-content", null, null, children, props.id);
		var holder = new Div({});
		holder.node.set(ashui.layout.Prop.Display, ashui.types.Style.Display.None);
		return holder;
	}
}

/** A link of the menu, or of a panel; `active` marks the page shown. **/
class NavigationMenuLink extends Component<{?active:Bool, ?onClick:ashui.input.Events.PointerEvent->Void, ?id:String}> {
	function render():Element {
		var box = Library.part("ui-nav-link", "a", props.active == true ? ["active" => ""] : null, children, props.id);
		ashui.text.InlineFlow.attach(box);
		var i = Interaction.of(box.node).setFocusable(true);
		if (props.onClick != null)
			i.onClick(props.onClick);
		return box;
	}
}
