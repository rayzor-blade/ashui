import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.ui.Div;
import ashui.ui.Text;

/**
	Styling cost: a page of cards from the components sheet and the
	user-agent sheet, styled once; then a class toggled on a tenth of the
	rows, and hover moved across rows. Prints the median of each over rounds.
**/
class CssBench {
	static function main() {
		ThemeState.init(DefaultTheme.bundle(), Dark);
		// Putting the sheets in force: the user-agent sheet and the components library's.
		var l0 = haxe.Timer.stamp();
		ashui.css.Css.useUserAgent();
		ashui.components.Library.use();
		var first = new LayoutTree();
		Owner.root(first, _ -> new Div({classes: ["ui-card"]}, first));
		first.flush();
		Sys.println('sheets in force, one element styled, ms ${Math.round((haxe.Timer.stamp() - l0) * 100000) / 100}');
		first.dispose();
		var rounds = 9, cards = 60, rows = 12;
		var builds = [], toggles = [], hovers = [];
		for (round in 0...rounds) {
			var tree = new LayoutTree();
			var picked = [for (_ in 0...cards * rows) Signal.make(["ui-menu-item"])];
			var t0 = haxe.Timer.stamp();
			var page = Owner.root(tree, _ -> new Div({classes: ["page"]}, [
				for (c in 0...cards)
					new Div({classes: ["ui-card"]}, [
						new Div({classes: ["ui-card-header"]}, [new Text('Card $c')]),
						new Div({classes: ["ui-menu"]}, [
							for (r in 0...rows) new Div({classes: picked[c * rows + r]}, [new Text('Row $r')])
						])
					])
			], tree));
			tree.flush();
			var t1 = haxe.Timer.stamp();
			for (i in 0...picked.length)
				if (i % 10 == round % 10)
					picked[i].set(["ui-menu-item", "ui-menu-item-active"]);
			tree.flush();
			var t2 = haxe.Timer.stamp();
			tree.computeLayout(page.node, 1200, 20000);
			// Hover moved row to row, each move styled before the next.
			var t3 = haxe.Timer.stamp();
			for (y in 0...40) {
				ashui.input.Pointer.move(tree, 100, 60 + y * 30);
				tree.flush();
			}
			var t4 = haxe.Timer.stamp();
			builds.push((t1 - t0) * 1000);
			toggles.push((t2 - t1) * 1000);
			hovers.push((t4 - t3) * 1000);
			tree.dispose();
		}
		function median(a:Array<Float>):String {
			a.sort(Reflect.compare);
			return Std.string(Math.round(a[a.length >> 1] * 100) / 100);
		}
		Sys.println('elements ${cards * (3 + rows * 2) + 1}');
		Sys.println('build+style ms ${median(builds)}');
		Sys.println('toggle 10% ms ${median(toggles)}');
		Sys.println('40 hover moves ms ${median(hovers)}');
	}
}
