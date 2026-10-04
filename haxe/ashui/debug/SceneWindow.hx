package ashui.debug;

import ashui.layout.Element;
import ashui.layout.LayoutTree;

/**
	A scene opened in a window instead of rendered to a file: what
	`Snapshot.scene`, `MotionRecorder.record` and `AlignProbe.record` do in
	a build with the window (`-D ashui_window`) run with `ASHUI_WINDOW`
	set, as `tools/snapshot/run.sh --window` does. The UI is live: it takes
	the pointer and keys, and `ASHUI_MOTION=overlay` draws the motion
	overlay over it. `ASHUI_WINDOW_SECONDS` closes it after that long, for
	a run nobody is watching, a profile or a measure of its memory.
**/
class SceneWindow {
	/** Whether scenes open in a window. **/
	public static function wanted():Bool {
		#if (hlwindow || ashui_window)
		return Sys.getEnv("ASHUI_WINDOW") != null;
		#else
		return false;
		#end
	}

	/**
		Opens `build` in a window `width` by `height`, titled `name`, until
		it is closed. A `script`, as a motion recording's `before`, plays on
		the window's clock at `fps`, frame by frame up to `frames`, so the
		recording's input happens live; then the window is the user's.
	**/
	public static function open(name:String, width:Int, height:Int, build:Void->Element, ?script:(Int, LayoutTree, Element) -> Void, fps = 60,
			frames = 0):Void {
		#if (hlwindow || ashui_window)
		var root:Null<Element> = null;
		if (script != null && frames > 0) {
			var elapsed = 0.0, done = 0, started = false;
			ashui.animation.AnimationScheduler.main.addTicker(dt -> {
				// Not until the UI is drawn, as a recording's first frame is, so a script finds what it looks for; its clock starts there.
				var app = ashui.app.WindowedApp.current;
				if (app == null || root == null || app.tree.order().length == 0)
					return true;
				if (started)
					elapsed += dt;
				started = true;
				// Every frame whose time has come, in order, each once.
				while (done < frames && done <= elapsed * fps) {
					script(done, app.tree, root);
					done++;
				}
				app.invalidate();
				return done < frames;
			});
		}
		var seconds = Std.parseFloat(Sys.getEnv("ASHUI_WINDOW_SECONDS"));
		if (!Math.isNaN(seconds))
			ashui.animation.AnimationScheduler.main.after(seconds, () -> {
				var app = ashui.app.WindowedApp.current;
				if (app != null)
					app.quit();
			});
		ashui.app.WindowedApp.run({title: name, width: width, height: height}, () -> root = build());
		#end
	}
}
