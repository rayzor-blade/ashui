package ashui.reactive;

/**
	Calls `react` with `read()` at creation, and again at each
	`LayoutTree.flush` where `read()` returns something new. Reacting at a
	flush keeps it outside Blinc's graph, so it may build and remove elements,
	which a computed or binding may not. Stops when the owner current at its
	creation is disposed.

	`read` runs at every flush, so it should be cheap: a computed's `get`
	returns its cached value unless something it read changed.
**/
class Watch<T> {
	static final active:Array<Watch<Dynamic>> = [];

	final read:Void->T;
	final react:T->Void;
	var last:T;
	var stopped = false;

	public function new(read:Void->T, react:T->Void) {
		this.read = read;
		this.react = react;
		last = read();
		react(last);
		active.push(cast this);
		Owner.onCleanup(stop);
	}

	public function stop():Void {
		stopped = true;
		active.remove(cast this);
	}

	function poll():Bool {
		if (stopped)
			return false;
		var now = read();
		if (now == last)
			return false;
		last = now;
		react(now);
		return true;
	}

	/** Polls every watch; true if any reacted. Reacting may add or stop watches. **/
	@:noCompletion public static function pollAll():Bool {
		var reacted = false;
		for (watch in active.copy())
			if (watch.poll())
				reacted = true;
		return reacted;
	}
}
