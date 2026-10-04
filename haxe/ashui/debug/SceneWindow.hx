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
	than a screen holds, which scrolls it; one wider than that window
	takes the window's width instead and lays out again. `ASHUI_WINDOW_CLICKS`,
	a number, clicks that many times, one every 150ms, each at the middle
	of a focusable element picked at random from those in view, a seeded
	pick so a run repeats: for finding what interaction breaks. `ASHUI_WINDOW_SECONDS` closes it after that long, for
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
		var clicks = Std.parseInt(Sys.getEnv("ASHUI_WINDOW_CLICKS"));
		if (clicks != null && clicks > 0) {
			var seed = 12345, since = 0.0, made = 0;
			ashui.animation.AnimationScheduler.main.addTicker(dt -> {
				var app = ashui.app.WindowedApp.current;
				if (app == null || app.tree.order().length == 0)
					return true;
				since += dt;
				if (since < 0.15)
					return true;
				since = 0;
				var tree = app.tree;
				var targets = [for (i in ashui.input.Interaction.inTree(tree)) if (i.focusable && tree.getBounds(i.node) != null
					&& tree.getBounds(i.node).width > 0) i];
				if (targets.length > 0) {
					seed = (seed * 1103515245 + 12345) & 0x7fffffff;
					var pick = targets[seed % targets.length];
					var b = tree.getBounds(pick.node);
					ashui.input.Pointer.move(tree, b.x + b.width / 2, b.y + b.height / 2);
					ashui.input.Pointer.press(tree);
					ashui.input.Pointer.release(tree);
					var who = ashui.css.Identity.of(tree, pick.node.id);
					Sys.println('click $made ${who == null ? "?" : who.classes().join(".")} at ${Std.int(b.x + b.width / 2)},${Std.int(b.y + b.height / 2)}');
					app.invalidate();
				}
				made++;
				return made < clicks;
			});
		}
		var seconds = Std.parseFloat(Sys.getEnv("ASHUI_WINDOW_SECONDS"));
		if (!Math.isNaN(seconds))
			ashui.animation.AnimationScheduler.main.after(seconds, () -> {
				var app = ashui.app.WindowedApp.current;
				if (app != null)
					app.quit();
			});
		var config = new ashui.app.WindowConfig().title(name).size(Std.int(Math.min(width, MAX_WIDTH)), Std.int(Math.min(height, MAX_HEIGHT)));
		ashui.app.WindowedApp.run(config, () -> {
			root = build();
			root.node.set(ashui.layout.Prop.FlexShrink, (0 : Single));
			// Wider than the window, it takes the window's width and lays out again, as a page does; narrower, it keeps its own.
			if (width > MAX_WIDTH)
				root.node.set(ashui.layout.Prop.WidthPercent, (1 : Single));
			var scroller = new ashui.ui.Div({flexDirection: ashui.types.Style.FlexDirection.Column, alignItems: ashui.types.Style.Align.Start, overflow: ashui.types.Style.Overflow.Scroll}, [root]);
			scroller.node.set(ashui.layout.Prop.WidthPercent, (1 : Single));
			scroller.node.set(ashui.layout.Prop.HeightPercent, (1 : Single));
			ashui.input.Scroll.attach(scroller.node, true, true);
			scroller;
		});
		#end
	}
}
