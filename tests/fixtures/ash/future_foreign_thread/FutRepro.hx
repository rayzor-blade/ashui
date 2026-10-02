/**
	Awaits `rounds` futures that a native thread resolves after `delay`
	microseconds, with null or, given `boxed`, with an Int boxed on that
	thread. Given `lookup`, the native finds the future functions with dlsym
	on the process, as hlwgpu does. Prints how many came back; a hang is the
	bug. Usage: FutRepro.hl <delay-us> <rounds> [boxed] [lookup]
**/
class FutRepro {
	@:hlNative("futrepro", "later") static function later(delayUs:Int, boxed:Bool, lookup:Bool):ash.Future<Dynamic>
		return null;

	@:hlNative("futrepro", "where") static function where(symbol:hl.Bytes):hl.Bytes
		return null;

	static function main() {
		var args = Sys.args();
		var delay = args.length > 0 ? Std.parseInt(args[0]) : 0;
		var rounds = args.length > 1 ? Std.parseInt(args[1]) : 100;
		var boxed = args.indexOf("boxed") >= 2;
		var lookup = args.indexOf("lookup") >= 2;
		if (lookup)
			Sys.println("dlsym finds hlp_future_resolve in " + @:privateAccess String.fromUTF8(where(@:privateAccess "hlp_future_resolve".toUtf8())));
		for (i in 0...rounds) {
			later(delay, boxed, lookup).await();
			if (i == 0)
				Sys.println("first resolved");
		}
		Sys.println('resolved $rounds');
	}
}
