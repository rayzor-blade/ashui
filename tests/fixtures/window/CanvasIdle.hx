// git-bug 364d4b2: paused canvas sleep, frame callback writes, resume and pause.
import ashui.animation.AnimationScheduler;
import ashui.app.WindowedApp;
import ashui.reactive.Signal;

class CanvasIdle {
	static function main() {
		var active = Signal.make(false), label = Signal.make("Paused");
		var armed = false, started = false, resumed = false, paused = false;
		var armedAt = 0.0, resumedAt = 0.0, paints = 0, atPause = 0;
		var callbackWritePainted = false, quiet = false;
		WindowedApp.run({title: "Canvas idle regression", width: 320, height: 160, onFrame: (_, _) -> {
			if (!started) {
				started = true;
				AnimationScheduler.main.after(0.8, () -> {
					armed = true;
					armedAt = haxe.Timer.stamp();
					WindowedApp.current.invalidate();
				});
			} else if (armed && !resumed) {
				resumed = true;
				// These writes occur after this frame's flush and render, with no active ticker.
				label.set("Playing");
				active.set(true);
			} else if (resumed && !paused) {
				if (resumedAt == 0) {
					resumedAt = haxe.Timer.stamp();
					AnimationScheduler.main.after(0.3, () -> {
						active.set(false);
						label.set("Paused again");
						paused = true;
						AnimationScheduler.main.after(0.1, () -> {
							atPause = paints;
							AnimationScheduler.main.after(0.4, () -> {
								quiet = paints == atPause && !AnimationScheduler.main.hasActive();
								WindowedApp.current.quit();
							});
						});
					});
				}
			}
		}}, () -> <div class="p-4 bg-surface flex flex-col">
			<canvas width={100} height={50} animate={active} paint={_ -> {
				paints++;
				if (label.get() == "Playing") callbackWritePainted = true;
			}} />
			<text>{label.get()}</text>
		</div>);
		var ok = resumed && paused && callbackWritePainted && resumedAt > armedAt && resumedAt - armedAt < 0.4 && quiet;
		Sys.println('resumed=$resumed paused=$paused callbackWritePainted=$callbackWritePainted quiet=$quiet resumeDelay=${resumedAt - armedAt}');
		Sys.println(ok ? "ALL PASSED" : "FAILED");
		Sys.exit(ok ? 0 : 1);
	}
}
