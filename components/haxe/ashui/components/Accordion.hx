package ashui.components;

import ashui.input.Focus;
import ashui.input.Interaction;
import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.reactive.Computed;
import ashui.reactive.Signal;
import ashui.reactive.Watch;
import ashui.ui.Component;
import ashui.ui.Svg;

typedef AccordionProps = {
	/** `single` (the default): one item open at a time; `multiple`: any. **/
	?type:String,
	/** The values of the items open. A signal is read and written; a constant sets them once. **/
	?value:IntoReactive<Array<String>>,
	/** With `single`, whether the open item closes when its trigger is clicked again; true by default. **/
	?collapsible:Bool,
	?onValueChange:Array<String>->Void,
	?id:String
}

/**
	Sections that open and close under their headings: `AccordionItem`s,
	each with a `value`, an `AccordionTrigger` (its heading) and an
	`AccordionContent`. A section opens and closes by layout animation, and
	the sections below make room for it as smoothly. In the triggers, the
	arrows, Home and End move among them. CSS: `.ui-accordion`,
	`.ui-accordion-item`, `.ui-accordion-trigger` (its `.ui-accordion-chevron`
	turning while open), `.ui-accordion-content`, each `[data-state]` open
	or closed.
**/
class Accordion extends Component<AccordionProps> {
	/** The values of the items open; the caller's signal when `value` was one. **/
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
		var items:Array<AccordionItem> = [for (c in children) if (Std.isOfType(c, AccordionItem)) cast c];
		for (item in items) {
			var v = item.props.value;
			item.bind(Computed.make(() -> (open.get().indexOf(v) >= 0 ? "open" : "closed" : Null<String>)), () -> {
				var now = open.get();
				var next = if (now.indexOf(v) >= 0) {
					if (multiple || props.collapsible != false) now.filter(x -> x != v) else now;
				} else multiple ? now.concat([v]) : [v];
				open.set(next);
				if (props.onValueChange != null)
					props.onValueChange(next);
			});
		}
		var box = Library.part("ui-accordion", null, null, children, props.id);
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

/** One section of an accordion, of a `value`: its trigger and its content. **/
class AccordionItem extends Component<{value:String, ?disabled:Bool, ?id:String}> {
	@:allow(ashui.components) var trigger:Null<AccordionTrigger> = null;
	var content:Null<AccordionContent> = null;
	final state = Signal.make((null : Null<Computed<Null<String>>>));

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

/** An accordion item's heading, which opens and closes it; a chevron turns while it is open. **/
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

/** What an accordion item shows while open, growing in and shrinking out by layout animation. **/
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
