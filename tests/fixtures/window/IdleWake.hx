import ashui.animation.AnimationScheduler;
import ashui.app.WindowedApp;
import ashui.reactive.Signal;

/** Real waits: a worker changes state, sets a timer, invalidates and quits without input. **/
class IdleWake {
	static function main() {
		var value = Signal.make(0);
		var reacted = false;
		var fired = false;
		var timerDelay = 0.0;
		var requested = 0.0;
		var repainted = false;
		var started = false;
		var done = new sys.thread.Lock();
		var begin = haxe.Timer.stamp();
		WindowedApp.run({title: "Idle wake regression", width: 320, height: 160, onFrame: (_, _) -> {
			if (requested > 0)
				repainted = true;
			if (started)
				return;
			started = true;
			var app = WindowedApp.current;
			sys.thread.Thread.create(() -> {
				Sys.sleep(1);
				value.set(42);
				Sys.sleep(0.5);
				var at = haxe.Timer.stamp();
				AnimationScheduler.main.after(0.3, () -> {
					timerDelay = haxe.Timer.stamp() - at;
					fired = true;
				});
				Sys.sleep(0.8);
				requested = haxe.Timer.stamp();
				app.invalidate();
				Sys.sleep(0.5);
				app.quit();
				done.release();
			});
		}}, () -> {
			new ashui.reactive.Watch(() -> value.get(), v -> reacted = v == 42);
			return <div class="p-6 bg-surface"><text>${'Value: '+value.get()}</text></div>;
		});
		var ok = done.wait(1) && reacted && fired && repainted && timerDelay >= 0.25 && timerDelay < 0.7
			&& haxe.Timer.stamp() - begin < 8;
		Sys.println('worker signal=$reacted timer=$fired delay=$timerDelay redraw=$repainted');
		Sys.println(ok ? "ALL PASSED" : "FAILED");
		Sys.exit(ok ? 0 : 1);
	}
}
