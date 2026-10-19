package ashui.core;

import ashui.animation.AnimationScheduler;

/** What an app asks of the runtime's memory when it lets go of a lot at once, as a page it has left. **/
class Memory {
	static var pending:Null<ashui.animation.AnimationScheduler.Timer> = null;

	/** Megabytes the program may hold above what it held after the last collection it asked for before `afterFrame` asks for another. **/
	public static var slack = 96.0;

	static var checkedAt = 0.0;
	static var baseline = 0.0;

	/**
		Called after a frame is drawn, which a window does: at most once a second, collects when the program holds more than `slack`
		megabytes beyond what it held after the last collection it asked for. An app that animates keeps allocating, and the runtime
		leaves that garbage until its own threshold, hundreds of megabytes on, which is memory the user sees while a track plays or a
		page moves and not after. A window that draws nothing never comes here, and a collection the runtime made on its own lowers
		what is held, so this asks only when garbage is piling up. A page does not ask: a collection there takes longer and the
		page's heap has a hard limit the runtime already works against.
	**/
	public static function afterFrame():Void {
		#if (hl && !wasm)
		var now = haxe.Timer.stamp();
		if (now - checkedAt < 1.0)
			return;
		checkedAt = now;
		if (hl.Gc.stats().currentMemory / 1048576 - baseline < slack)
			return;
		hl.Gc.major();
		baseline = hl.Gc.stats().currentMemory / 1048576;
		#end
	}

	/**
		Collects garbage `seconds` from now, once: asking again before then moves it later, so a burst of changes makes one collection
		after the last. The runtime collects when its own threshold is reached, which leaves what a page let go of in the process until
		then; this returns it when the page has settled. A target with no collector to ask does nothing.
	**/
	public static function collectSoon(seconds = 1.0):Void {
		#if hl
		if (pending != null)
			pending.cancel();
		pending = AnimationScheduler.main.after(seconds, () -> {
			pending = null;
			hl.Gc.major();
		});
		#end
	}
}
