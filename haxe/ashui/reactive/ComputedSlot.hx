package ashui.reactive;

#if ashui_rayzor
import ashui.core.externs.Handles;
import ashui.core.externs.BlincNative;

/**
	The host effect slot behind a computed, as Rayzor has them: native code cannot call a Haxe
	closure, so the computed's function is rerun by Haxe when the slot is due (`HostSlot`), and
	its result lives in a native signal that property bindings and other computeds track.

	A rerun happens only after a dependency was written, in the next flush or the next read.
	A computed holds this as a field, not as a base class, so that its own `ptr` stays the first
	field of the object, as every signal's is.
**/
class ComputedSlot extends HostSlot {
	final body:Void->Void;
	final after:Void->Void;

	/** True once freed. **/
	public var freed(default, null) = false;

	/** `body` evaluates the function; `after` writes its result to the native signal if it changed. **/
	public function new(body:Void->Void, after:Void->Void) {
		super(true, "");
		this.body = body;
		this.after = after;
	}

	override function evaluate():Void
		body();

	override function poll():Void {
		run();
		after();
	}

	/** The first evaluation, which makes the native signal. **/
	public function first():Void {
		run();
		after();
	}

	/** The result written to the native signal changed, which a flush must apply. **/
	public function wrote():Void
		noteMoved();

	/** Brings the computed up to date, and tracks it for the body or watch reading it. **/
	public function read(ptr:ComputedHandle):Void {
		HostSlot.catchUp();
		if (!freed)
			BlincNative.blinc_signal_touch(ptr);
	}

	/** Stops the computed and frees its native signal, for good. Calling it twice is harmless. **/
	public function free(ptr:ComputedHandle):Void {
		if (freed)
			return;
		freed = true;
		release();
		BlincNative.blinc_signal_release(ptr);
	}
}
#end
