package ashui.reactive;

/**
	Computed closures run inside Rust while Blinc's graph lock is held, so an
	exception must not unwind out of one. `wrap` catches it, the computed keeps
	its type's default, and the next `check` rethrows it. Nothing may be
	added to the graph meanwhile; `creating` says so instead of hanging.
**/
class Guard {
	static var pending:Null<haxe.Exception>;

	/** How many computed or watch closures are running, one inside another. **/
	static var evaluating = 0;

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
		Throws when `what` is being made while a computed or a watch
		evaluates: Blinc holds its graph's lock then, and adding to the graph
		would wait on it forever. Thrown there, it is rethrown after the
		evaluation, as any exception inside one is.
	**/
	public static inline function creating(what:String):Void {
		if (evaluating > 0)
			throw new haxe.Exception('$what was made while a computed or watch evaluated, which Blinc cannot do; make it before, outside the computation');
	}

	public static inline function check():Void {
		if (pending != null) {
			var e = pending;
			pending = null;
			throw e;
		}
	}
}
