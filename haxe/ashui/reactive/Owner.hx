package ashui.reactive;

import ashui.core.externs.Handles;
import ashui.core.externs.BlincNative;
import ashui.layout.LayoutTree;

/**
	Manages the lifetime of a UI subtree.
	Elements, computeds, watches and child owners created in this scope are
	cleaned up when it is disposed. Signals are not owned.

	Disposal first removes child owners, then runs cleanup callbacks in reverse
	registration order. Elements remove their nodes, computeds release their
	native handles and watches unsubscribe.

	Components, `For` items and `Show` branches each have an owner. Removing
	them disposes their contents. Start an application subtree with `Owner.root`.
	The owner also provides the `LayoutTree` for elements created in its scope.
	This follows SolidJS's ownership model.
**/
class Owner {
	/** The owner of what is being created now; null outside every owner. **/
	public static var current(default, null):Null<Owner>;

	/** The tree that elements made under this owner are built in. **/
	public var tree(default, null):LayoutTree;

	/** The owner this one is disposed with. **/
	public final parent:Null<Owner>;

	final children:Array<Owner> = [];
	final cleanups:Array<Void->Void> = [];
	var disposed = false;

	/**
		A child of `parent`, or of the current owner, with its tree unless
		given another.
	**/
	public function new(?tree:LayoutTree, ?parent:Owner) {
		this.parent = parent != null ? parent : current;
		parent = this.parent;
		this.tree = tree != null ? tree : parent != null ? parent.tree : null;
		if (this.tree == null)
			throw "an Owner needs a tree, or a current owner to take one from";
		if (parent != null)
			parent.children.push(this);
	}

	/** Runs `fn` with this owner current. **/
	public function run<R>(fn:Void->R):R {
		return tree.context.run(() -> runOwned(fn));
	}

	function runOwned<R>(fn:Void->R):R {
		var previous = current;
		current = this;
		try {
			var result = fn();
			current = previous;
			return result;
		} catch (e:haxe.Exception) {
			current = previous;
			throw e;
		}
	}

	/** Disposes this scope and removes it from its parent. Repeated calls have no effect. **/
	public function dispose():Void {
		tree.context.run(disposeOwned);
	}

	function disposeOwned():Void {
		if (disposed)
			return;
		disposed = true;
		while (children.length > 0)
			children.pop().dispose();
		while (cleanups.length > 0)
			cleanups.pop()();
		if (parent != null)
			parent.children.remove(this);
	}

	/**
		Runs `fn` in a new root owner for `tree`. Passes a function that disposes the root to `fn`.
		The new owner has no parent. This is similar to SolidJS's `createRoot`.
	**/
	public static function root<R>(tree:LayoutTree, fn:(dispose:Void->Void)->R):R {
		var previous = current;
		current = null;
		var owner = new Owner(tree);
		current = previous;
		return owner.run(() -> fn(owner.dispose));
	}

	/** Runs application-lifetime setup outside the current presentation owner (2abc23a). **/
	@:noCompletion public static function unowned<R>(fn:Void->R):R {
		var previous = current;
		current = null;
		try {
			var result = fn();
			current = previous;
			return result;
		} catch (e:haxe.Exception) {
			current = previous;
			throw e;
		}
	}

	/** Runs `fn` when the current owner is disposed; nothing outside an owner. **/
	public static function onCleanup(fn:Void->Void):Void {
		if (current != null)
			current.cleanups.push(fn);
	}

	/** Releases a computed made under the current owner when it is disposed. **/
	@:noCompletion public static function adoptComputed(ptr:ComputedHandle):Void {
		onCleanup(() -> BlincNative.blinc_computed_release(ptr));
	}
}
