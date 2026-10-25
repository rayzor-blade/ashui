package ashui.input;

import ashui.input.Events;
import ashui.layout.IntoReactive;
import ashui.layout.LayoutTree;
import ashui.layout.Node;
import ashui.reactive.Owner;
import ashui.reactive.Signal;

/**
	A node's input state: the signals its `hover:`, `active:`, `focus:`,
	`focus-visible:` and `disabled:` classes read, whether it takes focus, and
	the handlers its events call. Get it with `Interaction.of(node)`, which
	makes it the first time; in a template, `onClick={...}` and the other
	handler attributes, `focusable` and `disabled` go to it. `Pointer`,
	`Keyboard` and `Focus` keep it up to date. Each `on` method adds a
	handler and returns the interaction, so calls chain:
	`Interaction.of(node).setFocusable(true).onClick(e -> save())`.

	As with CSS's `:hover`, a node is hovered while the pointer is over it or
	over anything drawn inside it, and pressed while a press that began there
	is held. A disabled node and everything inside it takes no presses,
	clicks or focus; it is still hovered.
**/
class Interaction {
	static final byNode = new haxe.ds.ObjectMap<Node, Interaction>();
	static final byTree = new haxe.ds.ObjectMap<LayoutTree, TreeInteractions>();
	/** Lets the cascade attach deferred state readers when a node gains input (0973e0c). **/
	@:allow(ashui.css.NativeCascade)
	static final created:Array<Interaction->Void> = [];

	public final node:Node;

	/**
		The states below are Bools first; a signal for one is made the first time something reads it reactively, and kept in step after.
		Most elements are read through one or two, so an element with an interaction does not carry eight native handles.
	**/
	var bits = 0;
	var made:Null<Array<Null<Signal<Bool>>>> = null;

	/** The pointer is over it or over something inside it. **/
	public var hovered(get, never):Signal<Bool>;

	/** A press that began over it is held. **/
	public var pressed(get, never):Signal<Bool>;

	/** It has focus (see `Focus`). **/
	public var focused(get, never):Signal<Bool>;

	/** Focused, by the keyboard: the focus ring's case. **/
	public var focusVisible(get, never):Signal<Bool>;

	/** It or something inside it is focused. **/
	public var focusWithin(get, never):Signal<Bool>;

	/** It takes no presses, clicks or focus; set with `setDisabled`. **/
	public var disabled(get, never):Signal<Bool>;

	/** A checkbox or radio that is checked, or an option that is selected: CSS's `:checked`. **/
	public var checked(get, never):Signal<Bool>;

	/** A checkbox in neither state, CSS's `:indeterminate`. **/
	public var indeterminate(get, never):Signal<Bool>;

	function signalOf(state:InteractionState):Signal<Bool> {
		if (made == null)
			made = [for (_ in 0...8) null];
		var s = made[state];
		if (s == null)
			made[state] = s = Signal.make((bits & (1 << state)) != 0);
		return s;
	}

	function get_hovered():Signal<Bool> return signalOf(Hovered);
	function get_pressed():Signal<Bool> return signalOf(Pressed);
	function get_focused():Signal<Bool> return signalOf(Focused);
	function get_focusVisible():Signal<Bool> return signalOf(FocusVisible);
	function get_focusWithin():Signal<Bool> return signalOf(FocusWithin);
	function get_disabled():Signal<Bool> return signalOf(Disabled);
	function get_checked():Signal<Bool> return signalOf(Checked);
	function get_indeterminate():Signal<Bool> return signalOf(Indeterminate);

	/** Whether `state` holds now, read without making its signal; for code that does not follow it. **/
	public inline function is(state:InteractionState):Bool
		return (bits & (1 << state)) != 0;

	public inline function setHovered(on:Bool):Void setState(Hovered, on);
	public inline function setPressed(on:Bool):Void setState(Pressed, on);
	public inline function setFocused(on:Bool):Void setState(Focused, on);
	public inline function setFocusVisible(on:Bool):Void setState(FocusVisible, on);
	public inline function setFocusWithin(on:Bool):Void setState(FocusWithin, on);
	public inline function setChecked(on:Bool):Void setState(Checked, on);
	public inline function setIndeterminate(on:Bool):Void setState(Indeterminate, on);

	public inline function isHovered():Bool return is(Hovered);
	public inline function isPressed():Bool return is(Pressed);
	public inline function isFocused():Bool return is(Focused);
	public inline function isFocusVisible():Bool return is(FocusVisible);
	public inline function isFocusWithin():Bool return is(FocusWithin);
	public inline function isDisabled():Bool return is(Disabled);

	/** Sets `state`, and its signal when something has made one, and tells its listeners when it changed. **/
	public function setState(state:InteractionState, on:Bool):Void {
		var was = (bits & (1 << state)) != 0;
		if (on)
			bits |= 1 << state;
		else
			bits &= ~(1 << state);
		if (made != null) {
			var s = made[state];
			if (s != null)
				s.set(on);
		}
		if (was != on && listeners != null)
			for (l in listeners.copy())
				l();
	}

	var listeners:Null<Array<Void->Void>> = null;

	/** Calls `listener` whenever one of the states changes, with no signal made; the returned function removes it. **/
	public function onStateChange(listener:Void->Void):Void->Void {
		if (listeners == null)
			listeners = [];
		listeners.push(listener);
		return () -> if (listeners != null) listeners.remove(listener);
	}

	/** Whether the state CSS calls `name` holds now, read without making a signal; a form state not yet set reads false. **/
	public function stateNamed(name:String):Bool {
		return switch name {
			case "hover": is(Hovered);
			case "active": is(Pressed);
			case "focus": is(Focused);
			case "focus-visible": is(FocusVisible);
			case "focus-within": is(FocusWithin);
			case "checked": is(Checked);
			case "indeterminate": is(Indeterminate);
			case "placeholder-shown" | "valid" | "invalid" | "user-valid" | "user-invalid" | "required" | "optional":
				if (formStates == null) false else {
					var f = formStates.get(name);
					f != null && f.get();
				}
			case _: is(Disabled);
		}
	}

	/** Whether pressing it or tabbing to it gives it focus. **/
	public var focusable(default, null) = false;

	/** Marked `group`: what is inside it can follow its state with `group-` classes. **/
	public var isGroup(default, null) = false;

	/** Marked `peer`: its later siblings can follow its state with `peer-` classes. **/
	public var isPeer(default, null) = false;

	final handlers = new Map<String, Array<Dynamic->Void>>();
	var disabledWatch:Null<ashui.reactive.Watch<Bool>>;

	/** Disabled by its own `setDisabled`; `disabled` is that or any of `disablers`. **/
	var ownDisabled = false;

	/** What disables it from outside, as a disabled fieldset does what it holds. **/
	final disablers:Array<{}> = [];

	function new(node:Node) {
		this.node = node;
	}

	/** `node`'s interaction, made the first time it is asked for. Not to be called inside a computed. **/
	public static function of(node:Node):Interaction {
		if (!hooked) {
			hooked = true;
			ashui.css.Identity.forgetHooks.push(identity -> {
				var interaction = byNode.get(identity.node);
				if (interaction != null)
					interaction.dispose();
			});
		}
		var interaction = byNode.get(node);
		if (interaction != null)
			return interaction;
		interaction = new Interaction(node);
		byNode.set(node, interaction);
		var tree = node.tree;
		if (tree != null) {
			var all = byTree.get(tree);
			if (all == null)
				byTree.set(tree, all = new TreeInteractions());
			all.add(interaction);
		}
		Owner.onCleanup(interaction.dispose);
		for (hook in created) hook(interaction);
		return interaction;
	}

	static var hooked = false;

	var disposed = false;

	function dispose():Void {
		if (disposed)
			return;
		disposed = true;
		byNode.remove(node);
		var all = node.tree != null ? byTree.get(node.tree) : null;
		if (all != null) {
			all.remove(this);
			if (all.list.length == 0) byTree.remove(node.tree);
		}
		if (disabledWatch != null)
			disabledWatch.stop();
		Focus.forget(this);
	}

	/** `node`'s interaction if it has one. **/
	public static function find(node:Node):Null<Interaction>
		return byNode.get(node);

	/** The interactions of `tree`'s nodes. **/
	public static function inTree(tree:LayoutTree):Array<Interaction> {
		var all = byTree.get(tree);
		return all != null ? all.list : [];
	}

	/** The interaction of the node of `tree` with native id `id`, if it has one. **/
	public static function byId(tree:LayoutTree, id:haxe.Int64):Null<Interaction> {
		var all = byTree.get(tree);
		return all != null ? all.ids.get(TreeInteractions.key(id)) : null;
	}

	/** Lets pressing it or tabbing to it give it focus. **/
	public function setFocusable(value:Bool):Interaction {
		focusable = value;
		if (!value && is(Focused))
			Focus.clear(node.tree);
		return this;
	}

	/** Marks it `group`, as the `group` class does. **/
	public function markGroup():Interaction {
		isGroup = true;
		return this;
	}

	/** Marks it `peer`, as the `peer` class does. **/
	public function markPeer():Interaction {
		isPeer = true;
		return this;
	}

	/** The form states CSS reads, made the first time each is asked for (see `formState`). **/
	var formStates:Null<Map<String, Signal<Bool>>> = null;

	/**
		One of a form control's states, which its control sets and CSS's
		pseudo-classes of the same name read: `placeholder-shown`, `valid`,
		`invalid`, `user-valid` and `user-invalid` (once the user has
		changed it, or a form it is in was submitted), `required`,
		`optional`. False until the control sets it, so an element that is
		no form control matches none.
	**/
	public function formState(name:String):Signal<Bool> {
		if (formStates == null)
			formStates = new Map();
		var s = formStates.get(name);
		if (s == null)
			formStates.set(name, s = Signal.make(false));
		return s;
	}

	/** Disables it while `value`, a constant, signal or computed, is true. **/
	public function setDisabled(value:IntoReactive<Bool>):Interaction {
		if (disabledWatch != null) {
			disabledWatch.stop();
			disabledWatch = null;
		}
		switch (value : ReactiveType<Bool>) {
			case Const(v):
				setOwnDisabled(v);
			case Bound(s):
				disabledWatch = new ashui.reactive.Watch(() -> s.get(), setOwnDisabled);
			case Derived(c):
				disabledWatch = new ashui.reactive.Watch(() -> c.get(), setOwnDisabled);
		}
		return this;
	}

	/** Disables it while `on`, on behalf of `source`, whatever its own `setDisabled` says; each source is counted once. **/
	public function disableFrom(source:{}, on:Bool):Interaction {
		var has = disablers.indexOf(source) >= 0;
		if (on && !has)
			disablers.push(source);
		else if (!on && has)
			disablers.remove(source);
		applyDisabled();
		return this;
	}

	function setOwnDisabled(v:Bool):Void {
		ownDisabled = v;
		applyDisabled();
	}

	function applyDisabled():Void {
		var v = ownDisabled || disablers.length > 0;
		if (is(Disabled) != v)
			setState(Disabled, v);
		if (v && is(Focused))
			Focus.clear(node.tree);
	}

	/** Calls `handler` on a press and release of the primary button over it, or Enter or Space while it has focus. **/
	public function onClick(handler:PointerEvent->Void):Interaction
		return on("click", handler);

	/** A button went down over it. **/
	public function onPointerDown(handler:PointerEvent->Void):Interaction
		return on("pointerdown", handler);

	/** A button came up over it. **/
	public function onPointerUp(handler:PointerEvent->Void):Interaction
		return on("pointerup", handler);

	/** The pointer moved over it. **/
	public function onPointerMove(handler:PointerEvent->Void):Interaction
		return on("pointermove", handler);

	/** The pointer came over it or something inside it. Does not bubble. **/
	public function onPointerEnter(handler:PointerEvent->Void):Interaction
		return on("pointerenter", handler);

	/** The pointer is no longer over it or anything inside it. Does not bubble. **/
	public function onPointerLeave(handler:PointerEvent->Void):Interaction
		return on("pointerleave", handler);

	/** A wheel or trackpad scrolled over it, by the event's `deltaX` and `deltaY`. **/
	public function onWheel(handler:PointerEvent->Void):Interaction
		return on("wheel", handler);

	/** A key went down while it or something inside it had focus. **/
	public function onKeyDown(handler:KeyEvent->Void):Interaction
		return on("keydown", handler);

	/** A key came up while it or something inside it had focus. **/
	public function onKeyUp(handler:KeyEvent->Void):Interaction
		return on("keyup", handler);

	/** Text was typed while it or something inside it had focus. **/
	public function onTextInput(handler:TextInputEvent->Void):Interaction
		return on("textinput", handler);

	/** An input method's composition changed while it has focus; empty text when it ends. **/
	public function onComposition(handler:CompositionEvent->Void):Interaction
		return on("composition", handler);

	/** It gained focus. Does not bubble. **/
	public function onFocus(handler:FocusEvent->Void):Interaction
		return on("focus", handler);

	/** It lost focus. Does not bubble. **/
	public function onBlur(handler:FocusEvent->Void):Interaction
		return on("blur", handler);

	function on<E>(kind:String, handler:E->Void):Interaction {
		var list = handlers.get(kind);
		if (list == null)
			handlers.set(kind, list = []);
		list.push(cast handler);
		if (kind == "pointermove" && node.tree != null) {
			node.tree.invalidateHits();
			ashui.core.Work.notify();
		}
		return this;
	}

	@:allow(ashui.input)
	function hasMoveHandler():Bool {
		var list = handlers.get("pointermove");
		return list != null && list.length > 0;
	}

	/** The debugger reads existing handlers without creating an interaction. **/
	@:allow(ashui.debug)
	function handlerKinds():Array<String> {
		var kinds = [for (kind => list in handlers) if (list.length > 0) kind];
		kinds.sort(Reflect.compare);
		return kinds;
	}

	/** Calls its handlers of `kind` with `event`; false when it has none. **/
	@:allow(ashui.input)
	function fire(kind:String, event:InputEvent):Bool {
		var list = handlers.get(kind);
		if (list == null || list.length == 0)
			return false;
		event.at(node);
		for (handler in list.copy())
			handler(event);
		return true;
	}
}

/** One tree's interactions, by node and by native id. **/
private class TreeInteractions {
	public final list:Array<Interaction> = [];
	public final ids = new Map<String, Interaction>();

	public function new() {}

	public static inline function key(id:haxe.Int64):String
		return '${id.high}:${id.low}';

	public function add(i:Interaction):Void {
		list.push(i);
		ids.set(key(i.node.id), i);
	}

	public function remove(i:Interaction):Void {
		list.remove(i);
		ids.remove(key(i.node.id));
	}
}

/** The states an `Interaction` keeps. **/
enum abstract InteractionState(Int) to Int {
	var Hovered = 0;
	var Pressed = 1;
	var Focused = 2;
	var FocusVisible = 3;
	var FocusWithin = 4;
	var Disabled = 5;
	var Checked = 6;
	var Indeterminate = 7;
}
