package ashui.core;

import ashui.animation.AnimationScheduler;

/** What an app asks of the runtime's memory when it lets go of a lot at once, as a page it has left. **/
class Memory {
	static var pending:Null<ashui.animation.AnimationScheduler.Timer> = null;

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
