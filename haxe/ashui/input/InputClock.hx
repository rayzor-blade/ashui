package ashui.input;

/**
	The time input handling reads, in seconds: what decides a double-click,
	a select's typeahead and a pointer query's hover time. It is the system
	clock unless `source` is set, as a replayed input log sets it to the
	animation scheduler's clock so a replay decides these the same way
	every run.
**/
class InputClock {
	/** Where the time comes from; null for the system clock. **/
	public static var source:Null<Void->Float> = null;

	public static inline function now():Float
		return source != null ? source() : haxe.Timer.stamp();
}
