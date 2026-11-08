package ashui.core;

/**
	A byte buffer for native calls, kept and reused instead of made for each call: Rayzor has no collector and
	never frees a `Bytes`, so a buffer made per call is lost. `take` gives one of at least the size asked for,
	grown when a larger one is needed and not cleared. A native call reads or writes it only while it runs, so one
	buffer serves a purpose unless a use is still reading it when another use of the same buffer begins.
**/
class Scratch {
	var bytes:Null<NativeBytes> = null;
	var capacity = 0;

	public function new() {}

	/** At least `size` bytes, valid until the next `take`; it holds whatever the last use left. **/
	public function take(size:Int):NativeBytes {
		if (bytes == null || size > capacity) {
			capacity = Std.int(Math.max(Math.max(size, capacity * 2), 16));
			bytes = new NativeBytes(capacity);
		}
		return bytes;
	}
}
