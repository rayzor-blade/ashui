package ashui.input;

import ashui.input.Events;
import ashui.layout.IntoReactive;
import ashui.layout.LayoutTree;
import ashui.layout.Node;
import ashui.reactive.Owner;
import ashui.reactive.Signal;

/**
	Stores a node's input state and event handlers.

	Use `Interaction.of(node)` to get or create an interaction. HXX attributes
	such as `onClick`, `focusable` and `disabled` configure it automatically.
	`Pointer`, `Keyboard` and `Focus` update its state signals. These signals
	also drive state classes such as `hover:` and `focus-visible:`.

	Handler methods return the interaction, so calls can be chained:

	```haxe
	Interaction.of(node).setFocusable(true).onClick(_ -> save());
	```

	A node is hovered when the pointer is over it or any of its descendants.
	It stays pressed while a press that started on it is held. Disabled nodes
	and their descendants cannot receive presses, clicks or focus. They can
	still be hovered.
**/
class Interaction {
	static final byNode = new haxe.ds.ObjectMap<Node, Interaction>();
	static final byTree = new haxe.ds.ObjectMap<LayoutTree, TreeInteractions>();
	/** Notifies the CSS cascade when a node gains input state (0973e0c). **/
	@:allow(ashui.css.NativeCascade)
	static final created:Array<Interaction->Void> = [];

	public final node:Node;

	/**
		Stores states as bits. Creates each signal only when its property is read, then keeps it in sync.
		Most elements use only one or two states, so unused states need no native handles.
	**/
	var bits = 0;
	var made:Null<Array<Null<Signal<Bool>>>> = null;

	/** True when the pointer is over this node or any of its descendants. **/
	public var hovered(get, never):Signal<Bool>;

	/** True while a press that started on this node is held. **/
	public var pressed(get, never):Signal<Bool>;

	/** True when this node has focus. See `Focus`. **/
	public var focused(get, never):Signal<Bool>;

	/** True when this node has focus and should show a keyboard-style focus ring. **/
	public var focusVisible(get, never):Signal<Bool>;

	/** True when this node or any of its descendants has focus. **/
	public var focusWithin(get, never):Signal<Bool>;

	/** True when input is disabled. Change this state with `setDisabled`. **/
	public var disabled(get, never):Signal<Bool>;

	/** True for checked checkboxes and radios, or selected options. Maps to CSS `:checked`. **/
	public var checked(get, never):Signal<Bool>;

	/** True for an indeterminate checkbox. Maps to CSS `:indeterminate`. **/
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

	/** Reads `state` without creating a signal or tracking a reactive dependency. **/
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

	/** Updates the state and its signal, if one exists. Notifies listeners only when the state changes. **/
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

	/** Calls `listener` when any state changes, without creating signals. Returns an unsubscribe function. **/
	public function onStateChange(listener:Void->Void):Void->Void {
		if (listeners == null)
			listeners = [];
		listeners.push(listener);
		return () -> if (listeners != null) listeners.remove(listener);
	}

	/** Reads a CSS state by name without creating a signal. Unset form states return false. **/
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

	/** Whether this node can receive focus from a click or the Tab key. **/
	public var focusable(default, null) = false;

	/** Whether descendants can use `group-` classes to follow this node's state. **/
	public var isGroup(default, null) = false;

	/** Whether later siblings can use `peer-` classes to follow this node's state. **/
	public var isPeer(default, null) = false;

	final handlers = new Map<String, Array<Dynamic->Void>>();
	var disabledWatch:Null<ashui.reactive.Watch<Bool>>;

	/** Disabled by `setDisabled`. The effective state also includes external `disablers`. **/
	var ownDisabled = false;

	/** External sources that disable this node, such as a parent fieldset. **/
	final disablers:Array<{}> = [];

	function new(node:Node) {
		this.node = node;
	}

	/** Returns or creates the interaction for `node`. Do not call inside a computed. **/
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

	/** Returns the existing interaction for `node`, or null. Does not create one. **/
	public static function find(node:Node):Null<Interaction>
		return byNode.get(node);

	/** Returns the interactions registered in `tree`. **/
	public static function inTree(tree:LayoutTree):Array<Interaction> {
		var all = byTree.get(tree);
		return all != null ? all.list : [];
	}

	/** Returns the existing interaction for native node `id` in `tree`, or null. **/
	public static function byId(tree:LayoutTree, id:haxe.Int64):Null<Interaction> {
		var all = byTree.get(tree);
		return all != null ? all.ids.get(TreeInteractions.key(id)) : null;
	}

	/** Enables or disables focus from a click or the Tab key. Disabling clears existing focus. **/
	public function setFocusable(value:Bool):Interaction {
		focusable = value;
		if (!value && is(Focused))
			Focus.clear(node.tree);
		return this;
	}

	/** Enables `group-` classes on descendants. **/
	public function markGroup():Interaction {
		isGroup = true;
		return this;
	}

	/** Enables `peer-` classes on later siblings. **/
	public function markPeer():Interaction {
		isPeer = true;
		return this;
	}

	/** Lazily created form-state signals used by CSS. See `formState`. **/
	var formStates:Null<Map<String, Signal<Bool>>> = null;

	/**
		Returns a form-state signal, creating it with false as its initial value.

		Controls update these signals for CSS pseudo-classes: `placeholder-shown`,
		`valid`, `invalid`, `user-valid`, `user-invalid`, `required` and `optional`.
		User-validity states apply after user interaction or form submission.
		Elements that are not form controls leave these states unset.
	**/
	public function formState(name:String):Signal<Bool> {
		if (formStates == null)
			formStates = new Map();
		var s = formStates.get(name);
		if (s == null)
			formStates.set(name, s = Signal.make(false));
		return s;
	}

	/** Disables input while `value` is true. Accepts a constant, signal or computed. **/
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

	/**
		Adds or removes an external disable request from `source`. Each source is counted once.
		The node stays disabled while any source requests it, or its own `setDisabled` value is true.
	**/
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

	/** Calls `handler` after a primary-button click, or Enter or Space while this node has focus. **/
	public function onClick(handler:PointerEvent->Void):Interaction
		return on("click", handler);

	/** Registers a handler for pointer-button presses on this node. **/
	public function onPointerDown(handler:PointerEvent->Void):Interaction
		return on("pointerdown", handler);

	/** Registers a handler for pointer-button releases on this node. **/
	public function onPointerUp(handler:PointerEvent->Void):Interaction
		return on("pointerup", handler);

	/** Registers a handler for pointer movement over this node. **/
	public function onPointerMove(handler:PointerEvent->Void):Interaction
		return on("pointermove", handler);

	/** Registers a handler for pointer entry into this node or a descendant. Does not bubble. **/
	public function onPointerEnter(handler:PointerEvent->Void):Interaction
		return on("pointerenter", handler);

	/** Registers a handler for pointer exit from this node and all descendants. Does not bubble. **/
	public function onPointerLeave(handler:PointerEvent->Void):Interaction
		return on("pointerleave", handler);

	/** Registers a handler for a finger touching down on this node or a descendant. **/
	public function onTouchStart(handler:TouchEvent->Void):Interaction
		return on("touchstart", handler);

	/** Registers a handler for a touch that began here moving, wherever it has gone. **/
	public function onTouchMove(handler:TouchEvent->Void):Interaction
		return on("touchmove", handler);

	/** Registers a handler for a touch that began here lifting. **/
	public function onTouchEnd(handler:TouchEvent->Void):Interaction
		return on("touchend", handler);

	/** Registers a handler for a touch that began here being taken over by the system. **/
	public function onTouchCancel(handler:TouchEvent->Void):Interaction
		return on("touchcancel", handler);

	/** Registers a scroll handler. The event provides wheel or trackpad deltas as `deltaX` and `deltaY`. **/
	public function onWheel(handler:PointerEvent->Void):Interaction
		return on("wheel", handler);

	/** Registers a key-press handler for this node and its descendants. **/
	public function onKeyDown(handler:KeyEvent->Void):Interaction
		return on("keydown", handler);

	/** Registers a key-release handler for this node and its descendants. **/
	public function onKeyUp(handler:KeyEvent->Void):Interaction
		return on("keyup", handler);

	/** Registers a text-input handler for this node and its descendants. **/
	public function onTextInput(handler:TextInputEvent->Void):Interaction
		return on("textinput", handler);

	/** Registers an IME composition handler. An empty composition marks the end. **/
	public function onComposition(handler:CompositionEvent->Void):Interaction
		return on("composition", handler);

	/** Registers a focus-gained handler. Does not bubble. **/
	public function onFocus(handler:FocusEvent->Void):Interaction
		return on("focus", handler);

	/** Registers a focus-lost handler. Does not bubble. **/
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

	/** Dispatches `event` to handlers registered for `kind`. Returns false when none are registered. **/
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
