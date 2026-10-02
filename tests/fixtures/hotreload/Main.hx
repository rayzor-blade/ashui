import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.ui.HotReload;
import ashui.ui.Hxx.hxx;

/**
	Builds a Panel, sets its state, then polls for a reload. run.sh rebuilds
	this program with another Panel.hx while it runs; after the reload the
	panel must render from the new code and keep its state.
**/
class Main {
	static function main() {
		var tree = new LayoutTree();
		var panel:Panel = Owner.root(tree, _ -> hxx('<Panel />'));
		panel.count = 5;
		// A two-character string built at run time, the length of v1's
		// version() literal: a reload must leave it alone.
		probe = String.fromCharCode(122) + String.fromCharCode(122);
		Sys.println('ready ${describe(tree, panel)}');
		var deadline = Sys.time() + 20.0;
		while (Sys.time() < deadline) {
			if (HotReload.check()) {
				Sys.println('reloaded ${describe(tree, panel)}');
				return;
			}
			tree.flush();
			Sys.sleep(0.02);
		}
		Sys.println("no reload");
	}

	static var probe:String;

	static function describe(tree:LayoutTree, panel:Panel):String {
		tree.flush();
		tree.computeLayout(panel.node, 800, 600);
		var b = tree.getBounds(panel.node);
		var h = b == null ? -1 : b.height;
		return '${panel.version()} count=${panel.count} width=${b == null ? -1 : b.width} height=$h probe=$probe/${probe.length}';
	}
}
