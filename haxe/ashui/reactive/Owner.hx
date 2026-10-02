package ashui.reactive;

import ashui.core.externs.BlincNative;
import ashui.layout.LayoutTree;

/**
	Owns what is created while it is current: elements, computeds, and
	cleanups registered with `onCleanup`. Disposing an owner disposes its
	child owners, then runs its own cleanups, latest first; elements remove
	their nodes and computeds are released.

	It is also what an element takes its tree from, so components built under
	an owner pass none. The model is SolidJS's owner.
**/
class Owner {
	/** The owner of what is being created now; null outside every owner. **/
	public static var current(default, null):Null<Owner>;

	public var tree(default, null):LayoutTree;

	final parent:Null<Owner>;
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
