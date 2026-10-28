package ashui.reactive;

import ashui.core.externs.BlincNative;

/**
	Runs a reaction when a tracked value changes:

	```haxe
	new Watch(() -> count.get(), n -> trace(n));
	```

	`read` tracks its signal and computed dependencies. When a dependency
	changes, the next `LayoutTree.flush` reevaluates `read`. If the result
	differs, `react` receives the new value. Multiple changes before a flush
	are batched into one reaction. `react` also runs once during construction.

	Keep `read` read-only. `react` may update signals or add and remove UI
	elements. Call `stop` to unsubscribe, or let the current `Owner` stop the
	watch when disposed. This is similar to a SolidJS effect.

	Blinc tracks dependencies through a native slot. Haxe runs `read` between
	the slot's begin and end calls; native code does not retain its closure.
**/
class Watch<T> {
	/** Watches by slot. **/
	static var bySlot:Array<Null<Watch<Dynamic>>> = [];

	static var due = new hl.Bytes(4 * DUE);
	static inline var DUE = 256;

	/** Watches whose `read` gave a new value since they last reacted. **/
	static var changed:Array<Watch<Dynamic>> = [];

	final read:Void->T;
	final react:T->Void;
	final same:(T, T) -> Bool;
	final slot:Int;
	var latest:T;
	var reacted:T;
	var stopped = false;
	var queued = false;

	/**
		Do not create a watch inside a computed; evaluation holds the dependency-graph lock.
		`same` compares values before reacting. It defaults to `==`.
	**/
	public function new(read:Void->T, react:T->Void, ?same:(T, T) -> Bool) {
		this.read = ashui.core.UiContext.capture(read);
		var context = ashui.core.UiContext.current;
		this.react = value -> context.run(() -> react(value));
		this.same = same != null ? same : (a, b) -> a == b;
		Guard.creating("A watch");
		slot = BlincNative.blinc_host_effect_new();
		bySlot[slot] = cast this;
		run();
		Guard.check();
		reacted = latest;
		this.react(latest);
		Owner.onCleanup(stop);
	}

	/** `read` between the slot's begin and end, which track what it reads. **/
	function run():Void {
		BlincNative.blinc_host_effect_begin(slot);
		try {
			latest = read();
		} catch (e:haxe.Exception) {
			BlincNative.blinc_host_effect_end(slot);
			throw e;
		}
		BlincNative.blinc_host_effect_end(slot);
	}

	/** Stops reacting, for good; its owner's disposal does this too. **/
	public function stop():Void {
		if (stopped)
			return;
		stopped = true;
		bySlot[slot] = null;
		BlincNative.blinc_host_effect_release(slot);
	}

	/**
		Reevaluates pending watches and queues changed values for `runQueued`.
		Layout calls this after settling, so watches read final geometry before rendering.
	**/
	@:noCompletion public static function readDue():Void {
		while (true) {
			var n = BlincNative.blinc_host_effects_due(due, DUE);
			for (i in 0...n) {
				var watch = bySlot[due.getI32(i * 4)];
				if (watch == null || watch.stopped)
					continue;
				watch.run();
				Guard.check();
				if (!watch.queued && !watch.same(watch.reacted, watch.latest)) {
					watch.queued = true;
					changed.push(watch);
				}
			}
			if (n < DUE)
				return;
		}
	}

	/** Runs every due watch's `read`, then reacts for each whose value changed; true if any did. **/
	@:noCompletion public static function runQueued():Bool {
		readDue();
		if (changed.length == 0)
			return false;
		var batch = changed;
		changed = [];
		var any = false;
		for (watch in batch) {
			watch.queued = false;
			if (watch.stopped || watch.same(watch.reacted, watch.latest))
				continue;
			watch.reacted = watch.latest;
			watch.react(watch.latest);
			any = true;
		}
		return any;
	}
}
