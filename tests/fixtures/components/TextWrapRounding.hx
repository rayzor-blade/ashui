// A label whose box width comes from layout rounding must not wrap itself (git-bug 743b470).
import ashui.components.Button;
import ashui.components.DropdownMenu;
import ashui.css.Css;
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.theme.ThemeState;
import ashui.theme.themes.RestrainedTheme;

class TextWrapRounding {
	static var failures = 0;
	static var checks = 0;
	static function check(label:String, ok:Bool):Void {
		checks++;
		if (!ok) failures++;
		Sys.println((ok ? "ok   " : "FAIL ") + label);
	}

	static function alone(kind:String, label:String):{box:{width:Single, height:Single}, text:Null<{width:Single, height:Single}>} {
		var tree = new LayoutTree(), dispose:Void->Void = null;
		var view = Owner.root(tree, stop -> {
			dispose = stop;
			var el:ashui.layout.Element = switch kind {
				case "button": <button id="target">${label}</button>;
				case "button-sm": <button id="target" size={Sm}>${label}</button>;
				case _: <dropdown-menu><dropdown-menu-trigger id="target" size={Sm}>${label}</dropdown-menu-trigger><dropdown-menu-content><dropdown-menu-item>x</dropdown-menu-item></dropdown-menu-content></dropdown-menu>;
			};
			return <div class="flex flex-row items-start gap-2 p-4">${el}</div>;
		});
		tree.flush();
		tree.computeLayout(view.node, 800, 400);
		var t = tree.getBounds(new ashui.layout.Node(Css.query(tree, view.node.id, "#target")[0]));
		var texts = Css.query(tree, view.node.id, "#target text");
		var tb = texts.length == 0 ? null : tree.getBounds(new ashui.layout.Node(texts[0]));
		dispose();
		tree.dispose();
		return {box: {width: t.width, height: t.height}, text: tb == null ? null : {width: tb.width, height: tb.height}};
	}

	static function main() {
		ThemeState.init(RestrainedTheme.bundle(), Light);
		for (kind in ["button", "button-sm", "trigger"])
			for (label in ["Sky Port", "Do not save", "Don't save", "Move to Trash"]) {
				var r = alone(kind, label);
				var h = r.text != null ? r.text.height : r.box.height;
				// One line's height is the font's own line height; a wrap at
				// least doubles it. Any of these wrapping is the bug.
				check('$kind "$label" stays on one line (box ${r.box.width}x${r.box.height})', h < 24);
			}
		Sys.println('$checks checks, $failures failures');
		Sys.exit(failures == 0 ? 0 : 1);
	}
}
