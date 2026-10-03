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
	the handlers its events call. Made for a node the first time something
	asks for it; `Pointer`, `Keyboard` and `Focus` keep it up to date.

	As with CSS's `:hover`, a node is hovered while the pointer is over it or
	over anything drawn inside it, and pressed while a press that began there
	is held. A disabled node and everything inside it takes no presses,
	clicks or focus; it is still hovered.
**/
class Interaction {
	static final byNode = new haxe.ds.ObjectMap<Node, Interaction>();
	static final byTree = new haxe.ds.ObjectMap<LayoutTree, TreeInteractions>();

	public final node:Node;
	public final hovered:Signal<Bool>;
	public final pressed:Signal<Bool>;
	public final focused:Signal<Bool>;

	/** Focused, by the keyboard: the focus ring's case. **/
	public final focusVisible:Signal<Bool>;

	public final disabled:Signal<Bool>;

	/** Whether pressing it or tabbing to it gives it focus. **/
	public var focusable(default, null) = false;

	final handlers = new Map<String, Array<Dynamic->Void>>();
	var disabledWatch:Null<ashui.reactive.Watch<Bool>>;

	function new(node:Node) {
		this.node = node;
		hovered = Signal.make(false);
		pressed = Signal.make(false);
		focused = Signal.make(false);
		focusVisible = Signal.make(false);
		disabled = Signal.make(false);
	}

	/** `node`'s interaction, made the first time it is asked for. Not to be called inside a computed. **/
	public static function of(node:Node):Interaction {
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
		Owner.onCleanup(() -> {
			byNode.remove(node);
			if (tree != null)
				byTree.get(tree).remove(interaction);
			if (interaction.disabledWatch != null)
				interaction.disabledWatch.stop();
			Focus.forget(interaction);
		});
		return interaction;
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
		if (!value && focused.get())
			Focus.clear(node.tree);
		return this;
	}

	/** Disables it while `value` is true. **/
	public function setDisabled(value:IntoReactive<Bool>):Interaction {
		if (disabledWatch != null) {
			disabledWatch.stop();
			disabledWatch = null;
		}
		switch (value : ReactiveType<Bool>) {
			case Const(v):
				disabled.set(v);
			case Bound(s):
				disabledWatch = new ashui.reactive.Watch(() -> s.get(), v -> disabled.set(v));
			case Derived(c):
				disabledWatch = new ashui.reactive.Watch(() -> c.get(), v -> disabled.set(v));
		}
		if (disabled.get() && focused.get())
			Focus.clear(node.tree);
		return this;
	}

	/** Calls `handler` on a press and release of the primary button over it, or Enter or Space while it has focus. **/
	public function onClick(handler:PointerEvent->Void):Interaction
		return on("click", handler);

	public function onPointerDown(handler:PointerEvent->Void):Interaction
		return on("pointerdown", handler);

	public function onPointerUp(handler:PointerEvent->Void):Interaction
		return on("pointerup", handler);

	public function onPointerMove(handler:PointerEvent->Void):Interaction
		return on("pointermove", handler);

	/** The pointer came over it or something inside it. Does not bubble. **/
	public function onPointerEnter(handler:PointerEvent->Void):Interaction
		return on("pointerenter", handler);

	/** The pointer is no longer over it or anything inside it. Does not bubble. **/
	public function onPointerLeave(handler:PointerEvent->Void):Interaction
		return on("pointerleave", handler);

	public function onWheel(handler:PointerEvent->Void):Interaction
		return on("wheel", handler);

	public function onKeyDown(handler:KeyEvent->Void):Interaction
		return on("keydown", handler);

	public function onKeyUp(handler:KeyEvent->Void):Interaction
		return on("keyup", handler);

	public function onTextInput(handler:TextInputEvent->Void):Interaction
		return on("textinput", handler);

	/** An input method's composition changed while it has focus; empty text when it ends. **/
	public function onComposition(handler:CompositionEvent->Void):Interaction
		return on("composition", handler);

	public function onFocus(handler:FocusEvent->Void):Interaction
		return on("focus", handler);

	public function onBlur(handler:FocusEvent->Void):Interaction
		return on("blur", handler);

	function on<E>(kind:String, handler:E->Void):Interaction {
		var list = handlers.get(kind);
		if (list == null)
			handlers.set(kind, list = []);
		list.push(cast handler);
		return this;
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
