package ashui.components;

import ashui.input.Interaction;
import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.reactive.Computed;
import ashui.reactive.Signal;
import ashui.reactive.Watch;
import ashui.ui.Component;

typedef SidebarProps = {
	/** Whether the sidebar is collapsed to icons. A supplied signal is read and updated; a constant sets the initial state. **/
	?collapsed:IntoReactive<Bool>,
	?onCollapsedChange:Bool->Void,
	?id:String
}

/**
	Side navigation that collapses to icons with an animated width transition.
	Place labeled `SidebarItem` elements in `SidebarGroup` sections. Labels
	fade and group headings collapse as the sidebar narrows. Use
	`SidebarLayout` and `SidebarInset` to move the adjacent page with it.

	CSS: `.ui-sidebar` with expanded or collapsed `[data-state]`,
	`.ui-sidebar-toggle`, `.ui-sidebar-group`, `.ui-sidebar-group-label`,
	`.ui-sidebar-item` with `[data-active]` and `:hover`, plus
	`.ui-sidebar-icon` and `.ui-sidebar-label`.
**/
class Sidebar extends Component<SidebarProps> {
	public var collapsed(default, null):Signal<Bool>;

	static var chevron:Null<ashui.svg.SvgDocument> = null;

	function render():Element {
		collapsed = switch props.collapsed {
			case null: Signal.make(false);
			case Const(v): Signal.make(v);
			case Bound(s): s;
			case Derived(c):
				var s = Signal.make(c.get());
				new Watch(() -> c.get(), v -> s.set(v));
				s;
		}
		var c = collapsed;
		if (chevron == null)
			chevron = ashui.svg.SvgDocument.of(<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m15 18-6-6 6-6"/></svg>);
		var icon = new ashui.ui.Svg(chevron, {width: 16, height: 16});
		var toggle = Library.part("ui-sidebar-toggle", "button", null, [icon]);
		ashui.css.Identity.of(toggle.tree, toggle.node.id).setAttribute("type", "button");
		Interaction.of(toggle.node).setFocusable(true).onClick(_ -> {
			c.set(!c.get());
			if (props.onCollapsedChange != null)
				props.onCollapsedChange(c.get());
		});
		var box = Library.part("ui-sidebar", "nav", ["state" => Computed.make(() -> (c.get() ? "collapsed" : "expanded" : Null<String>))],
			([toggle] : Array<Element>).concat(children), props.id);
		return box;
	}
}

/** Sidebar items under a heading. The heading hides when the sidebar collapses. **/
class SidebarGroup extends Component<{?label:String, ?id:String}> {
	function render():Element {
		var parts:Array<Element> = [];
		if (props.label != null)
			parts.push(Library.part("ui-sidebar-group-label", null, null, [new ashui.ui.Text(props.label, {wrap: false})]));
		return Library.part("ui-sidebar-group", null, null, parts.concat(children), props.id);
	}
}

typedef SidebarItemProps = {
	/** SVG icon using the text color. Accepts a compiled SVG document or SVG markup. **/
	?icon:ashui.svg.Icon,
	/** Marks this item as the current page. **/
	?active:IntoReactive<Bool>,
	?onClick:ashui.input.Events.PointerEvent->Void,
	?id:String
}

/** Sidebar navigation item with an icon and an expanded-state label. **/
class SidebarItem extends Component<SidebarItemProps> {

	function render():Element {
		var parts:Array<Element> = [];
		if (props.icon != null) {
			var icon = new ashui.ui.Svg(props.icon, {width: 16, height: 16});
			ashui.css.Identity.of(icon.tree, icon.node.id).setClasses(["ui-sidebar-icon"]);
			parts.push(icon);
		}
		parts.push(Library.part("ui-sidebar-label", null, null, children));
		var data:Null<Map<String, IntoReactive<Null<String>>>> = switch props.active {
			case null: null;
			case Const(v): ["active" => (v ? "" : null : Null<String>)];
			case Bound(s): ["active" => Computed.make(() -> (s.get() ? "" : null : Null<String>))];
			case Derived(d): ["active" => Computed.make(() -> (d.get() ? "" : null : Null<String>))];
		}
		var box = Library.part("ui-sidebar-item", "a", data, parts, props.id);
		var i = Interaction.of(box.node).setFocusable(true);
		if (props.onClick != null)
			i.onClick(props.onClick);
		return box;
	}
}

/** Row containing a sidebar and its adjacent page. **/
class SidebarLayout extends Component<{?id:String}> {
	function render():Element
		return Library.part("ui-sidebar-layout", null, null, children, props.id);
}

/** Page area that follows the sidebar width transition. **/
class SidebarInset extends Component<{?id:String}> {
	function render():Element
		return Library.part("ui-sidebar-inset", "main", null, children, props.id);
}
