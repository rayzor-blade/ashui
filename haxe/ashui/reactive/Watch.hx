package ashui.reactive;

import ashui.core.externs.BlincNative;

/**
	Runs code when a value read from signals changes:
	`new Watch(() -> count.get(), n -> trace(n))`. Where a `Computed` derives
	a value, a watch acts on one.

	`read` is tracked as a computed's closure is: it runs again only when a
	signal or computed it read changes. A watch whose value may have changed
	is due: its `read` runs at the next `LayoutTree.flush`, or when a layout
	settles, and the flush calls `react` once with the new value, if it
	differs, so several changes before a flush make one reaction. `react` may set signals and build and
	remove elements; `read` must only read. `react` also runs once at
	creation. The watch stops when the owner current at its creation is
	disposed, or on `stop`. Modelled on a SolidJS effect.

	Blinc holds no closure for a watch, only its slot: at a flush the due
	slots come back in one call, and each `read` runs in Haxe between the
	slot's begin and end, which record what it reads.
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
	final same:(T, T)->Bool;
	final slot:Int;
	var latest:T;
	var reacted:T;
	var stopped = false;
	var queued = false;

	/**
		Not to be created inside a computed's closure: the dependency graph is
		locked while it runs. `same` decides when a new value needs no
		reaction; by default `==`.
	**/
	public function new(read:Void->T, react:T->Void, ?same:(T, T)->Bool) {
		this.read = read;
		this.react = react;
		this.same = same != null ? same : (a, b) -> a == b;
		Guard.creating("A watch");
		slot = BlincNative.blinc_host_effect_new();
		bySlot[slot] = cast this;
		run();
		Guard.check();
		reacted = latest;
		react(latest);
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
		Runs every due watch's `read`, queueing those whose value changed for
		`runQueued`. Layout calls it once it settles, so what a watch records
		from the layout, as a canvas's drawing at its size, is current before
		the frame is drawn.
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
