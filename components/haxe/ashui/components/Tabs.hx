package ashui.components;

import ashui.input.Focus;
import ashui.input.Interaction;
import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.reactive.Computed;
import ashui.reactive.Signal;
import ashui.reactive.Watch;
import ashui.ui.Component;

typedef TabsProps = {
	/** The value of the tab shown. A signal is read and written; a constant sets the first shown. Without it, the first tab's. **/
	?value:IntoReactive<String>,
	/** Called with the value of the tab chosen. **/
	?onValueChange:String->Void,
	?size:Size,
	?id:String
}

/**
	Tabs: a `TabsList` of `TabsTrigger`s, each with a `value`, and a
	`TabsContent` for each value, shown while its trigger is chosen. A
	click, Enter or Space chooses a trigger; in the list, the arrows, Home
	and End move to another and choose it. CSS: `.ui-tabs`,
	`.ui-tabs-list`, `.ui-tabs-trigger`, `.ui-tabs-content`, each
	`[data-state]` active or inactive (an inactive content is not shown),
	`.ui-tabs[data-size]`;
	`--ui-tabs-list-bg`, `-active-bg`, `-radius`, `-trigger-radius`.
**/
class Tabs extends Component<TabsProps> {
	/** The value of the tab shown; the caller's signal when `value` was one. **/
	public var value(default, null):Signal<String>;

	function render():Element {
		var triggers:Array<TabsTrigger> = [];
		var contents:Array<TabsContent> = [];
		function walk(list:Array<Element>) {
			for (c in list)
				if (Std.isOfType(c, TabsTrigger))
					triggers.push(cast c);
				else if (Std.isOfType(c, TabsContent))
					contents.push(cast c);
				else if (Std.isOfType(c, TabsList))
					walk(@:privateAccess (cast c : TabsList).children);
		}
		walk(children);
		value = switch props.value {
			case null: Signal.make(triggers.length > 0 ? triggers[0].props.value : "");
			case Const(v): Signal.make(v);
			case Bound(s): s;
			case Derived(c):
				var s = Signal.make(c.get());
				new Watch(() -> c.get(), v -> s.set(v));
				s;
		}
		var choose = (v:String) -> {
			if (value.get() == v)
				return;
			value.set(v);
			if (props.onValueChange != null)
				props.onValueChange(v);
		}
		// Each trigger and content follows this value, the state of each a computed of it.
		for (t in triggers) {
			var trigger = t;
			trigger.tabs.set(value);
			trigger.interaction.onClick(_ -> choose(trigger.props.value));
		}
		for (c in contents)
			c.tabs.set(value);
		// The arrows, Home and End move among the triggers that are enabled, choosing as they go.
		for (l in children)
			if (Std.isOfType(l, TabsList))
				Interaction.of(l.node).onKeyDown(e -> {
					var enabled = triggers.filter(t -> !t.interaction.disabled.get());
					var at = Lambda.findIndex(enabled, t -> t.interaction.focused.get());
					if (enabled.length == 0 || at < 0)
						return;
					var next = switch e.key {
						case Named(ArrowRight) | Named(ArrowDown): (at + 1) % enabled.length;
						case Named(ArrowLeft) | Named(ArrowUp): (at - 1 + enabled.length) % enabled.length;
						case Named(Home): 0;
						case Named(End): enabled.length - 1;
						case _: -1;
					}
					if (next < 0)
						return;
					e.preventDefault();
					Focus.set(enabled[next].interaction, true);
					choose(enabled[next].props.value);
				});
		return Library.part("ui-tabs", null, ["size" => (props.size == null ? Size.Md : props.size : String)], children, props.id);
	}
}

/** The row of a tabs' triggers. **/
class TabsList extends Component<{?id:String}> {
	function render():Element
		return Library.part("ui-tabs-list", null, null, children, props.id);
}

/** Active while `tabs`, the value of the tabs it is in, is `value`. **/
private function state(tabs:Signal<Null<Signal<String>>>, value:String):Computed<Null<String>>
	return Computed.make(() -> {
		var chosen = tabs.get();
		(chosen != null && chosen.get() == value ? "active" : "inactive" : Null<String>);
	});

/** A tab's trigger, which shows the content of its `value` when chosen. **/
class TabsTrigger extends Component<{value:String, ?disabled:IntoReactive<Bool>, ?id:String}> {
	public var interaction(default, null):Interaction;

	/** The value of the tabs it is in, set by them. **/
	public final tabs = Signal.make((null : Null<Signal<String>>));

	function render():Element {
		var box = Library.part("ui-tabs-trigger", null, ["state" => state(tabs, props.value)], children, props.id);
		interaction = Interaction.of(box.node).setFocusable(true);
		if (props.disabled != null)
			interaction.setDisabled(props.disabled);
		return box;
	}
}

/** What a tab shows while its trigger, of the same `value`, is chosen. **/
class TabsContent extends Component<{value:String, ?id:String}> {
	/** The value of the tabs it is in, set by them. **/
	public final tabs = Signal.make((null : Null<Signal<String>>));

	function render():Element
		return Library.part("ui-tabs-content", null, ["state" => state(tabs, props.value)], children, props.id);
}
