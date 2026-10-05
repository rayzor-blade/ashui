import ashui.app.WindowedApp;
import ashui.layout.Prop;
import ashui.theme.ThemeState;
import ashui.theme.Themed;
import ashui.types.Style;
import ashui.ui.Div;
import ashui.ui.Hxx.hxx;

/**
	Opens the demo card in a window, captures it, switches the scheme, lets
	the colours spring, captures again, then widens a pill whose width
	transitions, captures that and closes. Prints the frames each stage
	took; fails when a stage drew too few.
	Usage: WindowDemo.hl [capture-directory]
**/
class WindowDemo {
	static function main() {
		var dir = Sys.args().length > 0 ? Sys.args()[0] : null;
		pill = ashui.reactive.Signal.make((64 : Single));
		var stage = 0;
		var stageFrames = [0, 0, 0];
		var scheduler = ashui.animation.AnimationScheduler.main;
		// Checked on a timer, not per frame: once the width settles no further frame need come.
		function settled() {
			if (scheduler.hasActive()) {
				scheduler.after(0.05, settled);
				return;
			}
			capture(WindowedApp.current, dir, "window-transition");
			WindowedApp.current.quit();
		}
		var onFrame = (frame:Int, seconds:Float) -> {
			var app = WindowedApp.current;
			var theme = ThemeState.get();
			stageFrames[stage]++;
			if (stage == 0) {
				// A guard that does not wait on frames either.
				scheduler.after(15, () -> app.quit());
				capture(app, dir, "window-" + (theme.scheme() == Light ? "light" : "dark"));
				stage = 1;
				theme.toggleScheme();
			} else if (stage == 1 && !theme.isAnimating()) {
				capture(app, dir, "window-" + (theme.scheme() == Light ? "light" : "dark"));
				stage = 2;
				pill.set(200);
				scheduler.after(0.05, settled);
			}
		};
		var frames = WindowedApp.run({title: "ashui", width: 360, height: 240, onFrame: onFrame}, card);
		Sys.println('presented $frames frames: ${stageFrames[0]} before the switch, ${stageFrames[1]} for the scheme, ${stageFrames[2]} for the width');
		var ok = stageFrames[0] > 0 && stageFrames[1] > 1 && stageFrames[2] > 1;
		Sys.println(ok ? "ALL PASSED" : "FAILED");
		Sys.exit(ok ? 0 : 1);
	}

	static var pill:ashui.reactive.Signal<Single>;

	static function card():Div {
		var card:Div = hxx('
			<div width={280} height={160} margin={40} padding={16} gap={12} flexDirection={Column}
				cornerRadius={Themed.radius(Xl)} bg={Themed.brush(Surface)}
				borderColor={Themed.color(Border)} borderWidth={1}>
				<div height={56} flexShrink={0} cornerRadius={Themed.radius(Lg)} bg={Themed.brush(Primary)} />
				<div flexDirection={Row} gap={8}>
					<div class="transition-all duration-normal ease-state h-6 rounded-full bg-accent-subtle" width={pill} />
					<div width={48} height={24} cornerRadius={Themed.radius(Full)} bg={Themed.brush(SuccessBg)} />
				</div>
			</div>
		');
		card.node.set(Prop.Shadow, Themed.shadow(Lg));
		return new Div({width: 360, height: 240}, [card]);
	}

	/** The window's inner area as a PNG in `dir`, with macOS screencapture; nothing without a directory. **/
	static function capture(app:WindowedApp, dir:Null<String>, name:String):Void {
		if (dir == null || Sys.systemName() != "Mac")
			return;
		var w = app.window;
		var scale = w.scaleFactor();
		var left = w.x() + (w.outerWidth() - w.width()) / 2;
		var top = w.y() + w.outerHeight() - w.height();
		var region = [left, top, w.width(), w.height()].map(v -> Std.string(Math.round(v / scale))).join(",");
		Sys.command("screencapture", ["-x", "-R", region, '$dir/$name.png']);
		Sys.println('captured $dir/$name.png');
	}
}
