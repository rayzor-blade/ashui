import ashui.css.Css;
import ashui.css.Identity;
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.theme.ThemeState;
import ashui.theme.themes.RestrainedTheme;

/** A custom property on `:root` set under `@media`, as an app declares the zoom its layout is made at. **/
class CssRootZoom {
	static var checks = 0;
	static function check(name:String, ok:Bool, ?got:Dynamic) {
		if (!ok) throw name + (got == null ? "" : ' (got $got)');
		checks++;
		Sys.println('ok   $name');
	}
	static function main() {
		ThemeState.init(RestrainedTheme.bundle(), Light);
		Css.load(":root { --ui-zoom: 1; }
			@media (max-width: 1159px), (max-height: 879px) { :root { --ui-zoom: 0.9; } }
			@media (max-width: 1043px), (max-height: 791px) { :root { --ui-zoom: 0.8; } }
			@media (max-width: 927px), (max-height: 703px) { :root { --ui-zoom: 0.7; } }", "zoom.css");
		var tree = new LayoutTree();
		var root = Owner.root(tree, _ -> <div id="page" />);
		function zoomAt(w:Int, h:Int):Null<String> {
			Css.setViewport(w, h);
			Css.update();
			tree.flush();
			tree.computeLayout(root.node, w, h);
			return Css.computed(Identity.of(tree, root.node.id), "--ui-zoom");
		}
		var cases:Array<{w:Int, h:Int, zoom:Float}> = [{w: 1280, h: 900, zoom: 1}, {w: 1160, h: 880, zoom: 1}, {w: 1280, h: 879, zoom: 0.9}, {w: 1100, h: 900, zoom: 0.9}, {w: 1280, h: 700, zoom: 0.7}, {w: 1000, h: 900, zoom: 0.8}, {w: 900, h: 900, zoom: 0.7}, {w: 1920, h: 1080, zoom: 1}];
		for (c in cases) {
			var got = zoomAt(c.w, c.h);
			check('${c.w} by ${c.h} reads zoom ${c.zoom}', got != null && Std.parseFloat(got) == c.zoom, got);
		}
		Sys.println('$checks checks: ALL PASSED');
	}
}
