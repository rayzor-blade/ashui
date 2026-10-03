package ashui.reactive;

import ashui.core.externs.BlincNative;
import ashui.layout.LayoutTree;

/**
	The scope that cleans up after a piece of UI. What is created while an
	owner is current belongs to it: elements, computeds, watches, child
	owners, and functions registered with `onCleanup`. Disposing an owner
	disposes its child owners, then runs its own cleanups, latest first:
	elements remove their nodes from the tree, computeds are released and
	watches stop. Signals are not owned.

	Each component renders under an owner of its own, and each item of a
	`For` and branch of a `Show` under another, so removing one disposes
	everything it built. A program starts its UI under `Owner.root`. An
	owner also carries the `LayoutTree` its elements go in, so elements and
	components built under one need not be given a tree. The model is
	SolidJS's owner.
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

	/** Disposes what it owns, as above, and leaves its parent; once only. **/
	public function dispose():Void {
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
		Runs `fn` under a new owner of `tree` with no parent, passing it the
		function that disposes that owner; SolidJS's `createRoot`.
	**/
	public static function root<R>(tree:LayoutTree, fn:(dispose:Void->Void)->R):R {
		var previous = current;
		current = null;
		var owner = new Owner(tree);
		current = previous;
		return owner.run(() -> fn(owner.dispose));
	}

	/** Runs `fn` when the current owner is disposed; nothing outside an owner. **/
	public static function onCleanup(fn:Void->Void):Void {
		if (current != null)
			current.cleanups.push(fn);
	}

	/** Releases a computed made under the current owner when it is disposed. **/
	@:noCompletion public static function adoptComputed(ptr:hl.Abstract<"blinc_computed">):Void {
		onCleanup(() -> BlincNative.blinc_computed_release(ptr));
	}
}
