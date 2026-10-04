package ashui.debug;

import ashui.layout.Element;
import ashui.layout.LayoutTree;

/**
	A scene opened in a window instead of rendered to a file: what
	`Snapshot.scene`, `MotionRecorder.record` and `AlignProbe.record` do in
	a build with the window (`-D ashui_window`) run with `ASHUI_WINDOW`
	set, as `tools/snapshot/run.sh --window` does. The UI is live: it takes
	the pointer and keys, and `ASHUI_MOTION=overlay` draws the motion
	overlay over it. The scene keeps its own size, in a window no larger
	than a screen holds, which scrolls it both ways. `ASHUI_WINDOW_SECONDS` closes it after that long, for
	a run nobody is watching, a profile or a measure of its memory.
**/
class SceneWindow {
	/** The largest window a scene opens in, in layout units; a larger scene scrolls in it. **/
	static inline var MAX_WIDTH = 1280;

	static inline var MAX_HEIGHT = 860;

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
		ashui.app.WindowedApp.run({title: name, width: Std.int(Math.min(width, MAX_WIDTH)), height: Std.int(Math.min(height, MAX_HEIGHT))}, () -> {
			root = build();
			root.node.set(ashui.layout.Prop.FlexShrink, (0 : Single));
			var scroller = new ashui.ui.Div({flexDirection: ashui.types.Style.FlexDirection.Column, alignItems: ashui.types.Style.Align.Start, overflow: ashui.types.Style.Overflow.Scroll}, [root]);
			scroller.node.set(ashui.layout.Prop.WidthPercent, (100 : Single));
			scroller.node.set(ashui.layout.Prop.HeightPercent, (100 : Single));
			ashui.input.Scroll.attach(scroller.node, true, true);
			scroller;
		});
		#end
	}
}
