package ashui.reactive;

/**
	Computed closures run inside Rust while Blinc's graph lock is held, so an
	exception must not unwind out of one. `wrap` catches it, the computed keeps
	its type's default, and the next `check` rethrows it.
**/
class Guard {
	static var pending:Null<haxe.Exception>;

	public static function wrap(f:Void->Void):Void->Void {
		return () -> {
			try {
				f();
			} catch (e:haxe.Exception) {
				if (pending == null)
					pending = e;
			}
		};
	}

	public static inline function check():Void {
		if (pending != null) {
			var e = pending;
			pending = null;
			throw e;
		}
	}
}
