import ashui.css.Css;
import ashui.debug.TreeSnapshot;
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.reactive.Watch;
import ashui.theme.ThemeState;
import ashui.theme.themes.RestrainedTheme;

/** Global CSS theme subscriptions outlive presentation owners (git-bug 2abc23a). **/
class CssThemeOwnership {
	static var checks = 0;
	static function check(name:String, ok:Bool) {
		if (!ok) throw name;
		checks++;
		Sys.println('ok   $name');
	}
	static function color(tree:LayoutTree):String {
		tree.flush();
		tree.computeLayout(tree.root, 100, 100);
		return TreeSnapshot.take(tree).elements[0].style.get("color").toLowerCase();
	}
	static function expected():String return ("#" + StringTools.hex(ThemeState.get().color(Primary).rgb(), 6)).toLowerCase();
	static function watches():Int return [for (w in @:privateAccess Watch.bySlot) if (w != null) w].length;
	static function main() {
		var remaining = -1;
		for (round in 0...8) {
			ThemeState.init(RestrainedTheme.bundle(), round % 2 == 0 ? Dark : Light);
			var tree = new LayoutTree(), stop:Void->Void = null;
			var root = Owner.root(tree, dispose -> {
				stop = dispose;
				var owner = Owner.current;
				if (round == 0) Css.load("#probe { color: var(--primary); }", "theme-owner.css");
				check('round $round keeps the presentation owner current', Owner.current == owner);
				return <div id="probe" />;
			});
			tree.flush();
			tree.computeLayout(root.node, 100, 100);
			check('round $round installs the current theme after remount', color(tree) == expected());
			ThemeState.get().setScheme(round % 2 == 0 ? Light : Dark);
			check('round $round follows a live scheme change', color(tree) == expected());
			ThemeState.get().setColorOverride(Primary, ashui.theme.Rgba.fromHex(0x123abc));
			check('round $round follows token overrides', color(tree) == "#123abc");
			ThemeState.get().removeColorOverride(Primary);
			check('round $round follows override removal', color(tree) == expected());
			stop();
			tree.dispose();
			if (remaining < 0) remaining = watches();
			check('round $round leaves one global subscription without accumulating owner watches', remaining > 0 && watches() == remaining);
		}
		Sys.println('$checks checks: ALL PASSED');
	}
}
