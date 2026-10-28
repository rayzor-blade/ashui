package ashui.reactive;

/**
	Defers exceptions until native reactive evaluation returns to Haxe.
	Computed callbacks run while the dependency-graph lock is held, so an
	exception cannot unwind through the native callback. `wrap` catches it
	and returns the type's default value. The next `check` rethrows it in Haxe.
	Signal setters, computed getters and `LayoutTree.flush` call `check`.

	`creating` rejects watch construction during evaluation to prevent a deadlock.
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
		Rejects watch construction during computed or watch evaluation, which would deadlock on the graph lock.
		Signals and computeds may still be created. The exception is rethrown after evaluation returns to Haxe.
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
