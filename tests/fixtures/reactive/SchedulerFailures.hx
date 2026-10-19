import ashui.animation.AnimationScheduler;

/** A callback of the animation scheduler that throws costs the program that callback, not the others in its tick. **/
class SchedulerFailures {
	static var checks = 0;

	static function check(name:String, ok:Bool, ?detail:Dynamic):Void {
		if (!ok) {
			if (detail != null)
				Sys.println(Std.string(detail));
			throw name;
		}
		checks++;
		Sys.println('ok   $name');
	}

	static function main() {
		var s = new AnimationScheduler();
		var first = 0, last = 0, doomed = 0;
		s.addTicker(_ -> {
			first++;
			return true;
		});
		var thrower = s.addTicker(_ -> {
			doomed++;
			throw "a ticker's own failure";
		});
		s.addTicker(_ -> {
			last++;
			return true;
		});
		s.tick(0.016);
		s.tick(0.016);
		check("the tickers on both sides of one that throws run on every tick", first == 2 && last == 2, [first, last]);
		check("a ticker that throws is dropped, and says so", doomed == 1 && !thrower.running, [doomed, thrower.running]);
		check("the scheduler is still running what is left", s.hasActive());

		var done = s.addTicker(_ -> false);
		check("a ticker is running once it is added", done.running);
		s.tick(0.016);
		check("a ticker that returns false is no longer running", !done.running);

		var kept = s.addTicker(_ -> true);
		kept.cancel();
		check("a cancelled ticker is no longer running", !kept.running);

		var fired:Array<String> = [];
		s.after(0.01, () -> fired.push("a"));
		s.after(0.01, () -> throw "a timer's own failure");
		s.after(0.01, () -> fired.push("c"));
		s.tick(0.02);
		check("timers due with one that throws still run", fired.join(",") == "a,c", fired);

		Sys.println('$checks checks: ALL PASSED');
	}
}
