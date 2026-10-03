package ashui.layout;

import ashui.reactive.Owner;

/**
	Work to do once a node's children have changed. `LayoutTree.childrenHooks`
	runs before each change, while the children are still the old ones; work
	registered here runs at the start of the tree's next flush instead, after
	every change since, once however many there were, and before the
	stylesheet restyles, so what it sets is styled in the same flush.
**/
class AfterChildren {
	static final pending = new haxe.ds.ObjectMap<LayoutTree, Map<String, Void->Void>>();
	static var hooked = false;

	/**
		Calls `work` after a change to the children of any node `affects`
		accepts, at the start of the next flush; until the current owner is
		cleaned up.
	**/
	public static function watch(tree:LayoutTree, key:String, affects:haxe.Int64->Bool, work:Void->Void):Void {
		hook();
		var childrenHook = (t:LayoutTree, parent:haxe.Int64) -> if (t == tree && affects(parent)) schedule(tree, key, work);
		LayoutTree.childrenHooks.push(childrenHook);
		Owner.onCleanup(() -> {
			LayoutTree.childrenHooks.remove(childrenHook);
			var p = pending.get(tree);
			if (p != null)
				p.remove(key);
		});
	}

	static function schedule(tree:LayoutTree, key:String, work:Void->Void):Void {
		var p = pending.get(tree);
		if (p == null)
			pending.set(tree, p = new Map());
		p.set(key, work);
	}

	static function hook():Void {
		if (hooked)
			return;
		hooked = true;
		LayoutTree.flushHooks.unshift(tree -> {
			var p = pending.get(tree);
			if (p == null)
				return;
			pending.remove(tree);
			for (work in p)
				work();
		});
	}
}
