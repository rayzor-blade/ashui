package ashui.reactive;

/**
	Carries exceptions out of computed and watch closures. Those closures are
	called back from native code while the dependency graph is locked, so an
	exception must not unwind out of one: `wrap` catches it, the computed
	keeps its type's default, and the next `check`, which a signal's `set`,
	a computed's `get` and `LayoutTree.flush` make, rethrows it in Haxe. A
	watch may not be made meanwhile; `creating` says so instead of hanging.
**/
class Guard {
	static var pending:Null<haxe.Exception>;

	/** How many computed or watch closures are running, one inside another. **/
	static var evaluating = 0;

	/** `f` as a closure native code may call: an exception it throws is kept for `check`. **/
	public static function wrap(f:Void->Void):Void->Void {
		return () -> {
			evaluating++;
			try {
				f();
			} catch (e:haxe.Exception) {
				if (pending == null)
					pending = e;
			}
			evaluating--;
		};
	}

	/**
		Throws when `what`, a watch, is being made while a computed or a
		watch evaluates: it would wait forever on the graph's lock. Signals
		and computeds can be made then. Thrown there, it is rethrown after the
		evaluation, as any exception inside one is.
	**/
	public static inline function creating(what:String):Void {
		if (evaluating > 0)
			throw new haxe.Exception('$what was made while a computed or watch evaluated, which Blinc cannot do; make it before, outside the computation');
	}

	/** Rethrows the exception a wrapped closure kept, if any. **/
	public static inline function check():Void {
		if (pending != null) {
			var e = pending;
			pending = null;
			throw e;
		}
	}
}
