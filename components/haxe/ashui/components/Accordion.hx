package ashui.components;

import ashui.input.Focus;
import ashui.input.Interaction;
import ashui.layout.AfterChildren;
import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.reactive.Computed;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.reactive.Watch;
import ashui.ui.Component;
import ashui.ui.Svg;

typedef AccordionProps = {
	/** `single` (default) allows one open section; `multiple` allows several. **/
	?type:String,
	/** Values of the open sections. A supplied signal is read and updated; a constant sets the initial state. **/
	?value:IntoReactive<Array<String>>,
	/** Allows the open section to close when clicked again in single mode. Defaults to true. **/
	?collapsible:Bool,
	?onValueChange:Array<String>->Void,
	?id:String
}

/**
	Expandable sections with animated layout changes.

	Each `AccordionItem` has a unique `value`, an `AccordionTrigger` heading,
	and `AccordionContent`. Opening or closing a section also animates the
	positions of the sections below. Arrows, Home, and End navigate triggers.
	Items supplied by `<for>` and `<if>` are tracked as they change.

	CSS parts: `.ui-accordion`, `.ui-accordion-item`, `.ui-accordion-trigger`,
	`.ui-accordion-chevron`, and `.ui-accordion-content`. Parts expose
	`[data-state="open"]` or `[data-state="closed"]`; the chevron rotates on open.
**/
class Accordion extends Component<AccordionProps> {
	/** Values of the open sections. Uses the supplied signal when available. **/
	public var value(default, null):Signal<Array<String>>;

	function render():Element {
		value = switch props.value {
			case null: Signal.make(([] : Array<String>));
			case Const(v): Signal.make(v);
			case Bound(s): s;
			case Derived(c):
				var s = Signal.make(c.get());
				new Watch(() -> c.get(), v -> s.set(v));
				s;
		}
		var open = value;
		var multiple = props.type == "multiple";
		var box = Library.part("ui-accordion", null, null, children, props.id);
		var tree = box.tree, id = box.node.id, owner = Owner.current;
		var items:Array<AccordionItem> = [];
		var scopes = new haxe.ds.ObjectMap<AccordionItem, Owner>();
		// Finds the mounted items, going through fragments but not into an item, so a nested accordion keeps its own. Each item is bound once, under a scope of its own.
		function index() {
			var mounted:Array<AccordionItem> = [];
			function walk(node:haxe.Int64) {
				var item = AccordionItem.items.get(ashui.css.Identity.of(tree, node));
				if (item != null) {
					mounted.push(item);
					return;
				}
				for (child in tree.children(node))
					walk(child);
			}
			for (child in tree.children(id))
				walk(child);
			for (item => scope in scopes)
				if (mounted.indexOf(item) < 0) {
					scope.dispose();
					scopes.remove(item);
				}
			for (item in mounted) {
				if (scopes.exists(item))
					continue;
				var scope = new Owner(tree, owner);
				scopes.set(item, scope);
				var v = item.props.value;
				scope.run(() -> item.bind(Computed.make(() -> (open.get().indexOf(v) >= 0 ? "open" : "closed" : Null<String>)), () -> {
					var now = open.get();
					var next = if (now.indexOf(v) >= 0) {
						if (multiple || props.collapsible != false) now.filter(x -> x != v) else now;
					} else multiple ? now.concat([v]) : [v];
					open.set(next);
					if (props.onValueChange != null)
						props.onValueChange(next);
				}));
			}
			items = mounted;
		}
		index();
		AfterChildren.watch(tree, "accordion " + haxe.Int64.toStr(id), parent -> parent == id || tree.ancestors(parent).indexOf(id) >= 0, index);
		Owner.onCleanup(() -> {
			items = [];
			scopes.clear();
		});
		// The arrows, Home and End move among the triggers.
		Interaction.of(box.node).onKeyDown(e -> {
			var triggers = [for (i in items) if (i.trigger != null) i.trigger.interaction];
			var at = Lambda.findIndex(triggers, t -> t.focused.get());
			if (at < 0)
				return;
			var next = switch e.key {
				case Named(ArrowDown): (at + 1) % triggers.length;
				case Named(ArrowUp): (at - 1 + triggers.length) % triggers.length;
				case Named(Home): 0;
				case Named(End): triggers.length - 1;
				case _: -1;
			}
			if (next >= 0) {
				e.preventDefault();
				Focus.set(triggers[next], true);
			}
		});
		return box;
	}
}

/** One accordion section, identified by `value`, containing a trigger and content. **/
class AccordionItem extends Component<{value:String, ?disabled:Bool, ?id:String}> {
	@:allow(ashui.components) var trigger:Null<AccordionTrigger> = null;
	var content:Null<AccordionContent> = null;
	final state = Signal.make((null : Null<Computed<Null<String>>>));

	/** Maps rendered identities to their accordion items. **/
	@:allow(ashui.components) static final items = new haxe.ds.ObjectMap<ashui.css.Identity, AccordionItem>();

	function render():Element {
		for (c in children)
			if (Std.isOfType(c, AccordionTrigger))
				trigger = cast c;
			else if (Std.isOfType(c, AccordionContent))
				content = cast c;
		var s = state;
		var shown = Computed.make(() -> {
			var c = s.get();
			(c == null ? "closed" : c.get() : Null<String>);
		});
		if (trigger != null)
			trigger.state.set(shown);
		if (content != null)
			content.state.set(shown);
		var box = Library.part("ui-accordion-item", null, ["state" => shown], children, props.id);
		var identity = ashui.css.Identity.of(box.tree, box.node.id);
		items.set(identity, this);
		Owner.onCleanup(() -> items.remove(identity));
		// Items below one opening make room as smoothly as it opens.
		ashui.animation.LayoutAnimation.attach(box.node);
		return box;
	}

	@:allow(ashui.components)
	function bind(s:Computed<Null<String>>, toggle:Void->Void):Void {
		state.set(s);
		if (trigger != null && props.disabled != true)
			trigger.interaction.onClick(_ -> toggle());
		if (trigger != null && props.disabled == true)
			trigger.interaction.setDisabled(true);
	}
}

/** An accordion heading that toggles its section. The chevron indicates the open state. **/
class AccordionTrigger extends Component<{?id:String}> {
	@:allow(ashui.components) final state = Signal.make((null : Null<Computed<Null<String>>>));
	@:allow(ashui.components) var interaction:Interaction;

	static var chevron:Null<ashui.svg.SvgDocument> = null;

	function render():Element {
		if (chevron == null)
			chevron = ashui.svg.SvgDocument.of(<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M6 9l6 6 6-6"/></svg>);
		var icon = new Svg(chevron, {width: 16, height: 16});
		ashui.css.Identity.of(icon.tree, icon.node.id).setClasses(["ui-accordion-chevron"]);
		var label = Library.part("ui-accordion-label", null, null, children);
		ashui.text.InlineFlow.attach(label);
		var s = state;
		var box = Library.part("ui-accordion-trigger", "button", ["state" => Computed.make(() -> {
			var c = s.get();
			(c == null ? "closed" : c.get() : Null<String>);
		})], [label, icon], props.id);
		ashui.css.Identity.of(box.tree, box.node.id).setAttribute("type", "button");
		interaction = Interaction.of(box.node).setFocusable(true);
		return box;
	}
}

/** Section content that expands and collapses with layout animation. **/
class AccordionContent extends Component<{?id:String}> {
	@:allow(ashui.components) final state = Signal.make((null : Null<Computed<Null<String>>>));

	function render():Element {
		var s = state;
		var inner = Library.part("ui-accordion-content-inner", null, null, children);
		var box = Library.part("ui-accordion-content", null, ["state" => Computed.make(() -> {
			var c = s.get();
			(c == null ? "closed" : c.get() : Null<String>);
		})], [inner], props.id);
		ashui.animation.LayoutAnimation.attach(box.node);
		return box;
	}
}
