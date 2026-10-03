package ashui.input;

import ashui.input.Events;
import ashui.layout.LayoutTree;

/**
	Which node of each tree keyboard input goes to: keys and typed text are
	handed to the focused node and bubble up from it (see `Keyboard`). A
	node is focusable when its `Interaction` says so, by `setFocusable` or
	`focusable={true}` in a template. A focusable node gets focus when it
	is pressed or tabbed to; Tab and Shift+Tab move through the focusable
	nodes in document order, skipping disabled ones. The focused node's
	`Interaction.focused` signal is true, and its `focus` and `blur`
	handlers are called as focus comes and goes.
**/
class Focus {
	static final current = new haxe.ds.ObjectMap<LayoutTree, Interaction>();

	/** By tree, the interactions whose `focusWithin` is set. **/
	static final within = new haxe.ds.ObjectMap<LayoutTree, Array<Interaction>>();

	/** The focused node's interaction in `tree`, if any. **/
	public static function of(tree:LayoutTree):Null<Interaction>
		return current.get(tree);

	/** Focuses `target`; `visible` when the keyboard moved focus there. **/
	public static function set(target:Interaction, visible:Bool):Void {
		var tree = target.node.tree;
		if (tree == null || !target.focusable || target.disabled.get())
			return;
		var before = current.get(tree);
		if (before == target) {
			if (target.focusVisible.get() != visible)
				target.focusVisible.set(visible);
			return;
		}
		if (before != null)
			blur(before);
		current.set(tree, target);
		target.focused.set(true);
		target.focusVisible.set(visible);
		updateWithin(tree, target);
		target.fire("focus", new FocusEvent(target.node, visible));
	}

	/** Takes focus from whatever in `tree` has it. **/
	public static function clear(tree:Null<LayoutTree>):Void {
		if (tree == null)
			return;
		var before = current.get(tree);
		if (before != null) {
			current.remove(tree);
			blur(before);
			updateWithin(tree, null);
		}
	}

	/** Sets `focusWithin` on `target` and the interactions of its ancestors, and clears it elsewhere. **/
	static function updateWithin(tree:LayoutTree, target:Null<Interaction>):Void {
		var next = [];
		if (target != null) {
			next.push(target);
			for (id in tree.ancestors(target.node.id)) {
				var i = Interaction.byId(tree, id);
				if (i != null)
					next.push(i);
			}
		}
		var before = within.get(tree);
		if (before != null)
			for (i in before)
				if (next.indexOf(i) < 0)
					i.focusWithin.set(false);
		for (i in next)
			if (!i.focusWithin.get())
				i.focusWithin.set(true);
		within.set(tree, next);
	}

	/** Moves focus to the next focusable node after the focused one, or the previous with `backward`, wrapping. **/
	static final scopes = new haxe.ds.ObjectMap<LayoutTree, Array<ashui.layout.Node>>();

	/**
		Keeps Tab and Shift+Tab inside `node` until the returned function
		releases it, as a modal dialog keeps focus in itself. Scopes nest: the
		innermost holds.
	**/
	public static function trap(node:ashui.layout.Node):Void->Void {
		var tree = node.tree;
		var list = scopes.get(tree);
		if (list == null)
			scopes.set(tree, list = []);
		list.push(node);
		return () -> list.remove(node);
	}

	public static function move(tree:LayoutTree, backward = false):Void {
		var scope = scopes.get(tree);
		var inside = scope == null || scope.length == 0 ? null : scope[scope.length - 1];
		var order = [];
		for (id in tree.order()) {
			var i = Interaction.byId(tree, id);
			if (i != null && i.focusable && !i.disabled.get() && (inside == null || id == inside.id || tree.ancestors(id).indexOf(inside.id) >= 0))
				order.push(i);
		}
		if (order.length == 0)
			return;
		var at = order.indexOf(current.get(tree));
		var next = at < 0 ? (backward ? order.length - 1 : 0) : (at + (backward ? order.length - 1 : 1)) % order.length;
		set(order[next], true);
	}

	static function blur(i:Interaction):Void {
		i.focused.set(false);
		i.focusVisible.set(false);
		i.fire("blur", new FocusEvent(i.node, false));
	}

	@:allow(ashui.input.Interaction)
	static function forget(i:Interaction):Void {
		var tree = i.node.tree;
		if (tree != null && current.get(tree) == i)
			current.remove(tree);
		var flagged = tree != null ? within.get(tree) : null;
		if (flagged != null)
			flagged.remove(i);
	}
}
