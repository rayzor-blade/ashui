package ashui.components;

import ashui.components.Button;
import ashui.input.Focus;
import ashui.input.Interaction;
import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.reactive.Computed;
import ashui.reactive.Signal;
import ashui.reactive.Watch;
import ashui.ui.Component;
import ashui.ui.Div;

typedef DropdownMenuProps = {
	?open:IntoReactive<Bool>,
	/** Which side of its trigger it opens on; "bottom" by default. **/
	?side:String,
	?onOpenChange:Bool->Void,
	?id:String
}

/**
	A menu that drops down from a button: a `DropdownMenuTrigger` and a
	`DropdownMenuContent` of `DropdownMenuItem`s, with
	`DropdownMenuLabel`s and `DropdownMenuSeparator`s among them. Choosing
	an item, by a press or by Enter or Space, calls its `onSelect` and closes
	the menu; the arrows, Home and End move among the items; Escape or a
	press outside closes it, focus going back to the trigger. Opened by
	the keyboard, its first item takes focus. CSS: `.ui-dropdown-menu`
	(`[data-state]`), `.ui-menu` (the panel, `[data-side]`, `[closing]`),
	`.ui-menu-item` (`[data-variant="destructive"]`, `:hover`,
	`:focus-visible`, `:disabled`), `.ui-menu-shortcut`, `.ui-menu-label`,
	`.ui-menu-separator`, `.ui-dropdown-menu-trigger`.
**/
class DropdownMenu extends Component<DropdownMenuProps> {
	public var opened(default, null):Signal<Bool>;

	@:allow(ashui.components)
	static final registry = new Registry<DropdownMenu>();

	var panel:Null<Div> = null;
	var floating:Null<Floating> = null;

	/** Opens the menu with its top-left at `(x, y)`, as a context menu opens at the pointer. **/
	public function openAt(x:Float, y:Float):Void
		if (floating != null)
			floating.openAt(x, y);

	function render():Element {
		opened = switch props.open {
			case null: Signal.make(false);
			case Const(v): Signal.make(v);
			case Bound(s): s;
			case Derived(c):
				var s = Signal.make(c.get());
				new Watch(() -> c.get(), v -> s.set(v));
				s;
		}
		var open = opened;
		if (props.onOpenChange != null) {
			var first = true;
			new Watch(() -> open.get(), v -> if (first) first = false else props.onOpenChange(v));
		}
		var root = Library.part("ui-dropdown-menu", null, ["state" => Computed.make(() -> (open.get() ? "open" : "closed" : Null<String>))], children,
			props.id);
		registry.add(root.tree, root.node.id, this);
		var trigger:Null<Element> = null, content:Null<DropdownMenuContent> = null;
		for (c in children)
			if (Std.isOfType(c, DropdownMenuTrigger) || Std.isOfType(c, ashui.components.ContextMenu.ContextMenuTrigger))
				trigger = c;
			else if (Std.isOfType(c, DropdownMenuContent))
				content = cast c;
		if (content != null) {
			var p = content.panel;
			panel = p;
			registry.add(p.tree, p.node.id, this);
			// Its own state, so its opening animation plays as it opens, not when it is first styled out of sight.
			ashui.css.Identity.of(p.tree, p.node.id).bindAttribute("data-state", Computed.make(() -> (open.get() ? "open" : "closed" : Null<String>)));
			var floating = new Floating(opened, p);
			this.floating = floating;
			// Into the menu as it opens: its first item by the keyboard, the panel itself by a press, so the arrows work either way.
			floating.opened = () -> {
				var items = this.items();
				if (Focus.byKeyboard && items.length > 0)
					Focus.set(items[0], true);
				else
					Focus.set(Interaction.of(p.node), false);
			};
			if (trigger != null)
				floating.anchorTo(trigger, props.side == null ? "bottom" : props.side, 4);
			Interaction.of(p.node).setFocusable(true).onKeyDown(e -> {
				var items = this.items();
				if (items.length == 0)
					return;
				var at = Lambda.findIndex(items, i -> i.focused.get());
				switch e.key {
					case Named(ArrowDown):
						e.preventDefault();
						Focus.set(items[at < 0 ? 0 : (at + 1) % items.length], true);
					case Named(ArrowUp):
						e.preventDefault();
						Focus.set(items[at < 0 ? items.length - 1 : (at - 1 + items.length) % items.length], true);
					case Named(Home):
						e.preventDefault();
						Focus.set(items[0], true);
					case Named(End):
						e.preventDefault();
						Focus.set(items[items.length - 1], true);
					case Named(ArrowLeft) | Named(ArrowRight):
						if (sideKey(e.key.match(Named(ArrowRight)) ? 1 : -1))
							e.preventDefault();
					// Enter and Space click the focused item, as they click any focusable element.
					case _:
				}
			});
		}
		return root;
	}

	/** Left or right in the open menu: nothing for a dropdown menu; a menubar's moves to the next menu. True when it acted. **/
	function sideKey(dir:Int):Bool
		return false;

	/** The menu's enabled items, in order. **/
	function items():Array<Interaction> {
		var out = [];
		if (panel == null)
			return out;
		var tree = panel.tree;
		for (id in tree.order())
			if (tree.ancestors(id).indexOf(panel.node.id) >= 0) {
				var identity = ashui.css.Identity.of(tree, id);
				var i = Interaction.byId(tree, id);
				if (identity != null && identity.hasClass("ui-menu-item") && i != null && !i.disabled.get())
					out.push(i);
			}
		return out;
	}

	/** Chooses the item of `interaction`: its `onSelect`, then the menu closes. **/
	function select(interaction:Interaction):Void {
		var item = DropdownMenuItem.registry.near(interaction.node.tree, interaction.node.id);
		if (item != null && item.props.onSelect != null)
			item.props.onSelect();
		opened.set(false);
	}
}

/** The button that opens the menu, a chevron after its label; an outline button unless given a `variant`. **/
class DropdownMenuTrigger extends Component<{?variant:ButtonVariant, ?size:ButtonSize, ?id:String}> {
	static var chevron:Null<ashui.svg.SvgDocument> = null;

	function render():Element {
		if (chevron == null)
			chevron = ashui.svg.SvgDocument.parse('<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M6 9l6 6 6-6"/></svg>');
		var icon = new ashui.ui.Svg(chevron, {width: 14, height: 14});
		ashui.css.Identity.of(icon.tree, icon.node.id).setClasses(["ui-dropdown-menu-chevron"]);
		var button:Null<Button> = null;
		button = new Button({
			variant: props.variant == null ? Outline : props.variant,
			size: props.size,
			type: "button",
			id: props.id,
			onClick: _ -> {
				var m = DropdownMenu.registry.near(button.tree, button.node.id);
				if (m != null)
					m.opened.set(!m.opened.get());
			}
		}, children.concat([icon]));
		ashui.css.Identity.of(button.tree, button.node.id).addClasses(["ui-dropdown-menu-trigger"]);
		return button;
	}
}

/** The menu's panel: kept while closed, in the top layer while open. **/
class DropdownMenuContent extends Component<{?id:String}> {
	@:allow(ashui.components.DropdownMenu)
	var panel(default, null):Div;

	function render():Element {
		panel = Library.part("ui-menu", null, null, children, props.id);
		var holder = new Div({});
		holder.node.set(ashui.layout.Prop.Display, ashui.types.Style.Display.None);
		return holder;
	}
}

typedef DropdownMenuItemProps = {
	/** Called when it is chosen. **/
	?onSelect:Void->Void,
	/** A key combination shown at its end, as `⌘N`; only shown. **/
	?shortcut:String,
	/** A destructive action, in the error colour. **/
	?destructive:Bool,
	?disabled:IntoReactive<Bool>,
	?id:String
}

/** One of the menu's choices. **/
class DropdownMenuItem extends Component<DropdownMenuItemProps> {
	@:allow(ashui.components)
	static final registry = new Registry<DropdownMenuItem>();

	function render():Element {
		var label = Library.part("ui-menu-item-label", null, null, children);
		ashui.text.InlineFlow.attach(label);
		var parts:Array<Element> = [label];
		if (props.shortcut != null)
			parts.push(Library.part("ui-menu-shortcut", null, null, [new ashui.ui.Text(props.shortcut, {wrap: false})]));
		var box = Library.part("ui-menu-item", null, props.destructive == true ? ["variant" => "destructive"] : null, parts, props.id);
		registry.add(box.tree, box.node.id, this);
		var i = Interaction.of(box.node).setFocusable(true);
		if (props.disabled != null)
			i.setDisabled(props.disabled);
		i.onClick(_ -> {
			var m = DropdownMenu.registry.near(box.tree, box.node.id);
			if (m != null)
				@:privateAccess m.select(i);
		});
		return box;
	}
}

/** A heading over a group of items. **/
class DropdownMenuLabel extends Component<{?id:String}> {
	function render():Element {
		var box = Library.part("ui-menu-label", null, null, children, props.id);
		ashui.text.InlineFlow.attach(box);
		return box;
	}
}

/** A rule between groups of items. **/
class DropdownMenuSeparator extends Component<{?id:String}> {
	function render():Element
		return Library.part("ui-menu-separator", null, null, null, props.id);
}
