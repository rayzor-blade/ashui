import ashui.components.Breadcrumb;
import ashui.css.Css;
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.reactive.Reactive;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;

/** The text an inline flow makes for its lines goes with the flow: when its item is replaced and when its owner is disposed. **/
class InlineFlowRelease {
	static var checks = 0;

	static function check(name:String, ok:Bool, ?detail:Dynamic):Void {
		if (!ok)
			throw name + (detail == null ? "" : ' ($detail)');
		checks++;
		Sys.println('ok   $name');
	}

	static function texts():Int
		return Lambda.count(@:privateAccess ashui.ui.Text.byNode);

	static function main():Void {
		ThemeState.init(DefaultTheme.bundle(), Light);
		var before = texts();
		var file = signal("a/b/c/f0.hx"), tree = new LayoutTree();
		var dispose:Void->Void = null;
		var root = Owner.root(tree, stop -> {
			dispose = stop;
			return <div width={400} height={100}>
				<for {name in [file.get()]}>
					<breadcrumb>${[for (part in name.split("/")) <breadcrumb-item>${part}</breadcrumb-item>]}</breadcrumb>
				</for>
			</div>;
		});
		function settle()
			for (_ in 0...4) {
				Css.update();
				tree.flush();
				tree.computeLayout(root.node, 400, 100);
			}
		settle();
		var one = texts();
		check("a breadcrumb makes text", one > before, [before, one]);
		for (i in 1...21) {
			file.set('a/b/c/f$i.hx');
			settle();
		}
		check("replacing the breadcrumb twenty times leaves no text behind", texts() == one, [one, texts()]);
		dispose();
		check("disposing the owner takes the rest", texts() == before, [before, texts()]);
		tree.dispose();
		Sys.println('$checks checks: ALL PASSED');
	}
}
