import ashui.animation.AnimationScheduler;
import ashui.components.Floating;
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.theme.ThemeState;
import ashui.theme.themes.RestrainedTheme;
import ashui.ui.TopLayer;

/**
	A floating panel opened again while it is still closing, then closed: the first close's cleanup must not
	remove what the second owns, whatever the frames between.
**/
class FloatingReopen {
	static function main():Void {
		var runs = 0;
		for (dark in [true, false])
			for (modeless in [true, false])
				for (wait in [0, 1, 3, 6, 12])
					for (shown in [1, 5, 30]) {
						run(dark, modeless, wait, shown);
						runs++;
					}
		Sys.println('$runs checks: ALL PASSED');
	}

	static function run(dark:Bool, modeless:Bool, wait:Int, shown:Int):Void {
		ThemeState.init(RestrainedTheme.bundle(), dark ? Dark : Light);
		ashui.components.Library.use();
		var tree = new LayoutTree(), open = Signal.make(false), stop = () -> {};
		var floating:Null<Floating> = null;
		var root = Owner.root(tree, dispose -> {
			stop = dispose;
			var anchor = <div id="anchor" width={80} height={30} />;
			var panel = <div class="ui-hover-card" width={120} height={60}>Panel</div>;
			floating = new Floating(open, panel);
			floating.modeless = modeless;
			floating.anchorTo(anchor, "bottom", 4);
			return <div width={300} height={200}>{anchor}</div>;
		});
		function frames(n:Int) {
			for (_ in 0...n) {
				AnimationScheduler.main.tick(1 / 60);
				tree.flush();
				tree.computeLayout(root.node, 300, 200);
			}
		}
		frames(2);
		var label = 'dark=$dark modeless=$modeless wait=$wait shown=$shown';
		// Opened, closed, opened again `wait` frames into the close, closed again.
		open.set(true);
		frames(10);
		open.set(false);
		frames(wait);
		open.set(true);
		frames(shown);
		open.set(false);
		frames(40);
		if (TopLayer.openEntries().length != 0)
			throw 'An entry is left open: $label';
		// And it opens once more, as it was.
		open.set(true);
		frames(10);
		if (TopLayer.openEntries().length != 1)
			throw 'It did not open again: $label';
		stop();
		AnimationScheduler.main.tick(1);
		tree.flush();
		tree.dispose();
		Sys.println('ok   $label');
	}
}
