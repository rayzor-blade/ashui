import ashui.layout.LayoutTree;
import ashui.layout.Prop;
import ashui.reactive.Computed;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.reactive.Watch;
import ashui.text.Fonts;
import ashui.types.Style;
import ashui.ui.Div;
import ashui.ui.Hxx.hxx;
import ashui.ui.Text;

/**
	What a program in a page needs of ashui: signals and computeds across the
	native module's boundary, a watch, an hxx template laid out, and a bundled
	font. It needs no font of the system's, which a page has none of
	(git-bug 0c8c9a0). Runs in a page or under Ash.
**/
class PageSmoke {
	static var checks = 0;
	static var failures = 0;

	static function check(name:String, ok:Bool, ?detail:Dynamic) {
		if (ok) {
			checks++;
			Sys.println('ok   $name');
		} else {
			failures++;
			Sys.println('FAIL $name' + (detail == null ? "" : ": " + Std.string(detail)));
		}
	}

	static function near(a:Float, b:Float)
		return Math.abs(a - b) < 0.01;

	static function main() {
		Fonts.embed("fixtures/text/regular.ttf");

		var count = Signal.make(1);
		count.set(2);
		check("an Int signal is written and read", count.get() == 2, count.get());
		var amount = Signal.make((200 : Single));
		var quarter = amount.computed(v -> (v / 4 : Single));
		check("a computed reads its signal", near(quarter.get(), 50), quarter.get());
		amount.set(100);
		check("a computed follows a write", near(quarter.get(), 25), quarter.get());
		var label = Signal.make("a");
		label.set("b");
		check("a String signal is written and read", label.get() == "b", label.get());

		var seen:Array<Int> = [];
		var tree = new LayoutTree();
		var owner = Owner.root(tree, _ -> {
			new Watch(() -> count.get(), v -> seen.push(v));
			return new Div({width: 10, height: 10}, tree);
		});
		count.set(3);
		tree.flush();
		check("a watch reacts to a write at the next flush", seen.length == 2 && seen[1] == 3, seen);

		var layoutTree = new LayoutTree();
		var root:Div = Owner.root(layoutTree, _ -> <div flexDirection={Column} width={200}><text>One</text><text>Two</text></div>);
		layoutTree.flush();
		layoutTree.computeLayout(root.node, 400, 400);
		var kids = layoutTree.children(root.node.id);
		var first = layoutTree.getBounds(Text.at(kids[0]).node), second = layoutTree.getBounds(Text.at(kids[1]).node);
		check("an hxx template is laid out: its second line is below the first", first != null && second != null && near(second.y, first.y + first.height),
			[first, second]);

		var fontTree = new LayoutTree();
		var text = new Text("MMMM", {fontSize: 16}, fontTree);
		text.node.set(Prop.FontFamily, "Blinc Embedded Fixture");
		var holder = new Div({flexDirection: Column, alignItems: Start}, [text], fontTree);
		fontTree.flush();
		fontTree.computeLayout(holder.node, 400, 100);
		var width = fontTree.getBounds(text.node).width;
		check("text is set in a bundled face: four capital Ms at 16px are 32px wide", near(width, 32), width);

		Sys.println(failures == 0 ? 'ALL PASSED ($checks)' : '$failures FAILED');
		if (failures > 0)
			Sys.exit(1);
	}
}
