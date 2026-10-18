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
	}

	/** Call after queuing work; writes in the running UI turn need no wake. **/
	public static inline function notify():Void {
		var callback = wake;
		if (callback != null) {
			#if target.threaded
			if (sys.thread.Thread.current() != owner)
				deliver(callback);
			else
			#end
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
