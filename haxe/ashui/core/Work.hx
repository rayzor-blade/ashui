package ashui.core;

/** Connects queued UI work to the host's sleeping event loop. **/
@:noCompletion
class Work {
	static var wake:Null<Void->Void>;
	#if target.threaded
	static var owner:Null<sys.thread.Thread>;
	#end

	/** The host installs its wake operation for the lifetime of its loop. **/
	public static function listen(callback:Null<Void->Void>):Void {
		#if target.threaded
		owner = callback == null ? null : sys.thread.Thread.current();
		#end
		wake = callback;
		turn = late = false;
	}

	/** Whether the host's loop is in the middle of a turn: its own thread's writes then need no wake. **/
	static var turn = false;

	/** Set by a notify in the loop's own turn, for the loop to ask before it sleeps. **/
	static var late = false;

	/** The host's loop starts a turn. **/
	public static function begin():Void
		turn = true;

	/** The loop's flush takes what was queued so far. **/
	public static function settle():Void
		late = false;

	/** The loop's turn is over: whether work was queued after its last `settle`, which another turn must take before it sleeps. **/
	public static function end():Bool {
		turn = false;
		var left = late;
		late = false;
		return left;
	}

	/** Call after queuing work; the loop's own thread, in its turn, needs no wake, as the flush that ends the turn takes what it wrote. **/
	public static inline function notify():Void {
		var callback = wake;
		if (callback != null) {
			#if target.threaded
			if (sys.thread.Thread.current() != owner)
				deliver(callback);
			else
			#end
			if (turn)
				late = true;
			else
				callback();
		}
	}

	#if target.threaded
	/** A wake from another thread is a hint: one that cannot be delivered, as from a thread in a page, leaves the work queued all the same. **/
	static function deliver(callback:Void->Void):Void {
		try
			callback()
		catch (_:haxe.Exception) {}
	}
	#end
}
