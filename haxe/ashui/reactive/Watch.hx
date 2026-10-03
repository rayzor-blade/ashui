package ashui.reactive;

import ashui.core.externs.BlincNative;

/**
	Runs code when a value read from signals changes:
	`new Watch(() -> count.get(), n -> trace(n))`. Where a `Computed` derives
	a value, a watch acts on one.

	`read` is tracked as a computed's closure is: it runs again only when a
	signal or computed it read changes. A watch whose value changed is
	queued, and the next `LayoutTree.flush` calls `react` once with the
	latest value, so several changes before a flush make one reaction.
	Reacting at the flush, outside the dependency graph, is what lets `react`
	set signals and build and remove elements; `read` must only read.
	`react` also runs once at creation. The watch stops when the owner
	current at its creation is disposed, or on `stop`. Modelled on a SolidJS
	effect; `read` runs in a Blinc effect.
**/
class Watch<T> {
	static var queue:Array<Watch<Dynamic>> = [];

	final react:T->Void;
	final same:(T, T)->Bool;
	var effect:hl.Abstract<"blinc_effect">;
	var latest:T;
	var reacted:T;
	var queued = false;
	var stopped = false;

	/**
		Not to be created inside a computed's closure or another watch's
		`read`: the dependency graph is locked while they run. `same` decides
		when a new value needs no reaction; by default `==`.
	**/
	public function new(read:Void->T, react:T->Void, ?same:(T, T)->Bool) {
		this.react = react;
		this.same = same != null ? same : (a, b) -> a == b;
		var first = true;
		Guard.creating("A watch");
		effect = BlincNative.blinc_effect(Guard.wrap(() -> {
			latest = read();
			if (first)
				first = false;
			else if (!queued && !stopped) {
				queued = true;
				queue.push(cast this);
			}
		}));
		Guard.check();
		reacted = latest;
		react(latest);
		Owner.onCleanup(stop);
	}

	/** Stops reacting, for good; its owner's disposal does this too. **/
	public function stop():Void {
		if (stopped)
			return;
		stopped = true;
		BlincNative.blinc_effect_release(effect);
	}

	/** Reacts for every queued watch whose value changed; true if any did. **/
	@:noCompletion public static function runQueued():Bool {
		if (queue.length == 0)
			return false;
		var batch = queue;
		queue = [];
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
