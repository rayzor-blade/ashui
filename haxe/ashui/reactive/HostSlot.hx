package ashui.reactive;

import ashui.core.NativeBytes;
import ashui.core.externs.BlincNative;

/**
	A reaction the host runs: native code keeps its dependencies and reports it due, and Haxe
	reruns its body between the slot's begin and end calls (`Watch`, and computeds on Rayzor,
	where native code cannot call a Haxe closure).

	Nothing polls. A slot is due only after a signal it read was written, and that write already
	woke the host's loop, so an idle window has no due slot and runs nothing.
**/
class HostSlot {
	static var bySlot:Array<Null<HostSlot>> = [];

	static var due = new NativeBytes(4 * DUE);
	static inline var DUE = 256;

	/** Rounds of the drain that mean computeds keep changing each other. **/
	static inline var ROUNDS = 1000;

	/** Slots taken from native code that a drain left for `readAll`: a watch reads after layout settles. **/
	static var parked:Array<HostSlot> = [];

	/** Bodies running now, one inside another. **/
	static var running = 0;

	/** Set once a computed exists: its writes can make more slots due, so a drain asks again until none is. **/
	static var chained = false;

	/** Whether a computed wrote a native value since `takeMoved`. **/
	static var moved = false;

	final slot:Int;
	final computed:Bool;
	var held = false;

	/** True once the slot is released. **/
	public var stopped(default, null) = false;

	/** `what` names the thing being made for `Guard.creating`; empty for none. **/
	function new(computed:Bool, what:String) {
		if (what != "")
			Guard.creating(what);
		this.computed = computed;
		if (computed)
			chained = true;
		slot = BlincNative.blinc_host_effect_new();
		bySlot[slot] = this;
	}

	/** The body: what it reads is what the slot depends on. **/
	function evaluate():Void {}

	/** Reruns after native code reported it due. **/
	function poll():Void {}

	/** Runs `evaluate` between the slot's begin and end calls. **/
	function run():Void {
		running++;
		BlincNative.blinc_host_effect_begin(slot);
		try {
			evaluate();
		} catch (e:haxe.Exception) {
			BlincNative.blinc_host_effect_end(slot);
			running--;
			throw e;
		}
		BlincNative.blinc_host_effect_end(slot);
		running--;
	}

	/** Gives the slot back, for good. **/
	function release():Void {
		if (stopped)
			return;
		stopped = true;
		bySlot[slot] = null;
		BlincNative.blinc_host_effect_release(slot);
	}

	/** A computed wrote a native value, which a flush must apply. **/
	function noteMoved():Void
		moved = true;

	/** Whether a computed wrote a native value since the last call. **/
	public static function takeMoved():Bool {
		var was = moved;
		moved = false;
		return was;
	}

	/**
		Takes what native code reports due. Computeds run now, until none is due, as one's write
		can make another due; the rest are parked for `readAll`. The first exception a body throws
		is rethrown after the rest have run, so no due slot is lost.
	**/
	static function drain():Void {
		var failure:Null<haxe.Exception> = null;
		var rounds = 0;
		while (true) {
			var n = BlincNative.blinc_host_effects_due(due, DUE);
			for (i in 0...n) {
				var host = bySlot[due.getI32(i * 4)];
				if (host == null || host.stopped)
					continue;
				if (!host.computed) {
					if (!host.held) {
						host.held = true;
						parked.push(host);
					}
					continue;
				}
				try {
					host.poll();
				} catch (e:haxe.Exception) {
					if (failure == null)
						failure = e;
				}
			}
			if (n == 0 || (n < DUE && !chained))
				break;
			if (++rounds > ROUNDS) {
				if (failure == null)
					failure = new haxe.Exception("computeds keep changing each other: a computed depends on itself, directly or through others");
				break;
			}
		}
		if (failure != null)
			throw failure;
	}

	/**
		Brings every due computed up to date, for a read between a write and the next flush.
		Watches taken meanwhile wait for `readAll`. Does nothing inside a body, which a rerun corrects.
	**/
	public static function catchUp():Void {
		if (chained && running == 0)
			drain();
	}

	/** Reruns everything due: computeds first, then the watches, which read their final values. **/
	public static function readAll():Void {
		var failure:Null<haxe.Exception> = null;
		try {
			drain();
		} catch (e:haxe.Exception) {
			failure = e;
		}
		var batch = parked;
		parked = [];
		for (host in batch) {
			host.held = false;
			if (host.stopped)
				continue;
			try {
				host.poll();
			} catch (e:haxe.Exception) {
				if (failure == null)
					failure = e;
			}
		}
		if (failure != null)
			throw failure;
	}
}
