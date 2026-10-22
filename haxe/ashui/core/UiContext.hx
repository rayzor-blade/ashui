package ashui.core;

/** Window-local services. Callbacks keep the context they were created in. */
class UiContext {
	public static var current(default, null):UiContext = new UiContext();

	final values = new haxe.ds.ObjectMap<Dynamic, Dynamic>();
	final parent:Null<UiContext>;
	final cleanups:Array<Void->Void> = [];
	public var disposed(default, null) = false;

	public function new(?parent:UiContext)
		this.parent = parent;

	public function run<T>(fn:Void->T):T {
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

	/** Wraps a deferred read in its creation context. */
	public static function capture<T>(fn:Void->T):Void->T {
		var context = current;
		return () -> context.run(fn);
	}

	@:allow(ashui.core.UiContext.Local)
	function get<T>(key:Local<T>):T {
		if (!values.exists(key)) {
			var value = parent != null && key.fork != null ? key.fork(parent.get(key)) : key.create();
			values.set(key, value);
		}
		return cast values.get(key);
	}

	/** Drops services after all UI owners in this context have been disposed. */
	public function onCleanup(fn:Void->Void):Void
		cleanups.push(fn);

	public function clear():Void {
		disposed = true;
		while (cleanups.length > 0)
			cleanups.pop()();
		values.clear();
	}
}

/** A service lazily created once in each UI context. */
@:access(ashui.core.UiContext)
class Local<T> {
	@:allow(ashui.core.UiContext) final create:Void->T;
	@:allow(ashui.core.UiContext) final fork:Null<T->T>;

	public var value(get, set):T;

	public function new(create:Void->T, ?fork:T->T) {
		this.create = create;
		this.fork = fork;
	}

	function get_value():T
		return UiContext.current.get(this);

	function set_value(value:T):T {
		UiContext.current.values.set(this, value);
		return value;
	}
}
