import ashui.components.Badge;
import ashui.css.Css;
import ashui.layout.Element;
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.ui.Text;

/** Nested HXX must type children in the surrounding Haxe scope (66cc2f7). **/
class MarkupComprehensions {
	static var checks = 0;
	static function check(name:String, ok:Bool):Void {
		if (!ok) throw name;
		checks++; Sys.println('ok   $name');
	}
	static function item(name:String):Element return <text>item {name}</text>;
	static function main():Void {
		ashui.theme.ThemeState.init(ashui.theme.themes.DefaultTheme.bundle(), Dark);
		var names = ["a", "b"], rows = [["a", "b"], ["c"]], suffix = Signal.make("first");
		var tree = new LayoutTree(), stop:Void->Void = null;
		var root = Owner.root(tree, dispose -> {
			stop = dispose;
			return <div>
				<div id="dollar">{[for (name in names) <div>${item(name)}</div>]}</div>
				<div id="braces">{[for (name in names) <div>{item(name)}</div>]}</div>
				<div id="nested">{[for (row in rows) <div>{[for (name in row) <div>{item(name)}</div>]}</div>]}</div>
				<div id="component">{[for (name in names) <badge>{item(name)}</badge>]}</div>
				<div id="bound">{[for (name in names) <div id={"row-" + name}><text>{name + suffix.get()}</text></div>]}</div>
				<div id="conditional">{[for (name in names) if (name == "b") <div>{item(name)}</div>]}</div>
				<div id="iterator">{[for (i in 0...2) <div>{item(Std.string(i))}</div>]}</div>
				<div id="lambda">{names.map(name -> <div>{item(name)}</div>)}</div>
			</div>;
		});
		function content(id:String):String {
			var strings = [];
			for (node in Css.query(tree, root.node.id, "#" + id + " text")) {
				var text = Text.at(node); if (text != null) strings.push(text.text());
			}
			return strings.join("|");
		}
		tree.flush(); tree.computeLayout(root.node, 800, 800);
		check("dollar interpolation inserts element children", content("dollar") == "item a|item b");
		check("brace interpolation inserts element children", content("braces") == "item a|item b");
		check("nested comprehensions retain each row's scope", content("nested") == "item a|item b|item c");
		check("component children keep their element type", content("component") == "item a|item b");
		check("attributes retain the loop variable", Css.query(tree, root.node.id, "#row-a").length == 1);
		check("reactive content reads the loop variable", content("bound") == "afirst|bfirst");
		suffix.set("second"); tree.flush();
		check("reactive content still updates", content("bound") == "asecond|bsecond");
		check("filtered comprehensions insert the surviving element", content("conditional") == "item b");
		check("range iterators preserve their integer type", content("iterator") == "item 0|item 1");
		check("lambda bodies lower in their parameter scope", content("lambda") == "item a|item b");
		stop(); tree.dispose();
		Sys.println('$checks checks: ALL PASSED');
	}
}
