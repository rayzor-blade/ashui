import ashui.components.Button;
import ashui.core.render.Snapshot;
import ashui.layout.LayoutTree;
import ashui.reactive.Computed;
import ashui.reactive.Signal;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Style;
import ashui.ui.Hxx.hxx;

/**
	The smallest program that uses the whole stack: signals and a computed, a layout written in HXX, real pointer and keyboard
	input found by hit testing, and a render through the GPU to PNG files.

	It runs the same on Ash and on Rayzor. Each step of the script presses or types on the screen, and the program then checks
	what the signals hold. It exits with status 1 if a check fails. The frames land in `$ASHUI_SNAPSHOT_DIR` as
	`counter-000.png` and on.
**/
class Counter {
	static var failed = 0;

	static function main() {
		ThemeState.init(DefaultTheme.bundle(), Light);
		var page = ThemeState.get().color(Background);

		var count = Signal.make(0);
		var name = Signal.make("");
		var loud = Signal.make(false);
		var label = Computed.make(() -> "Count: " + count.get());
		var greeting = Computed.make(() -> {
			var who = name.get() == "" ? "stranger" : name.get();
			return (loud.get() ? "HELLO, " : "Hello, ") + who + "!";
		});

		var build = () -> hxx('
			<div id="page" flexDirection={Column} padding={24} gap={12} width={360}>
				<h3>Counter</h3>
				<p id="shown">{label}</p>
				<div flexDirection={Row} gap={8}>
					<button id="dec" variant={Outline} onClick={_ -> count.set(count.get() - 1)}>-</button>
					<button id="inc" onClick={_ -> count.set(count.get() + 1)}>+</button>
					<button id="loud" variant={Outline} onClick={_ -> loud.set(!loud.get())}>Shout</button>
				</div>
				<input id="name" type="text" placeholder="Your name" value={name} />
				<p id="greeting">{greeting}</p>
			</div>
		');

		Snapshot.sequence("counter", 360, 380, build, 60, 16, (frame, tree, root) -> switch frame {
			case 1:
				click(tree, root, "inc");
				click(tree, root, "inc");
				click(tree, root, "inc");
				click(tree, root, "dec");
				check("two after three presses of + and one of -", count.get() == 2);
			case 2:
				click(tree, root, "name");
				ashui.input.Keyboard.text(tree, "Ada");
				check("typing reaches the bound signal", name.get() == "Ada");
			case 3:
				click(tree, root, "loud");
				check("a press toggles its signal", loud.get());
				check("the computed follows both signals", greeting.get() == "HELLO, Ada!");
			case 14:
				check("the label shows the count", ashui.ui.Text.at(textNode(tree, root, "shown")).text() == "Count: 2");
			case _:
		}, page.rgb(), page.a, 2.0);

		for (p in ashui.css.Css.problems)
			Sys.println("css: " + p);
		Sys.println(failed == 0 ? "ALL PASSED" : "FAILED " + failed);
		if (failed > 0)
			Sys.exit(1);
	}

	static function check(what:String, ok:Bool):Void {
		if (!ok)
			failed++;
		Sys.println((ok ? "ok   " : "FAIL ") + what);
	}

	/** Presses and releases the primary button at the centre of the element with `id`. **/
	static function click(tree:LayoutTree, root:ashui.layout.Element, id:String):Void {
		var b = tree.getBounds(new ashui.layout.Node(byId(tree, root.node.id, id)));
		ashui.input.Pointer.move(tree, b.x + b.width / 2, b.y + b.height / 2);
		ashui.input.Pointer.press(tree);
		ashui.input.Pointer.release(tree);
	}

	/** The id of the text node inside the element with `id`. **/
	static function textNode(tree:LayoutTree, root:ashui.layout.Element, id:String):haxe.Int64 {
		var parent = byId(tree, root.node.id, id);
		for (child in tree.children(parent))
			if (ashui.ui.Text.at(child) != null)
				return child;
		throw 'no text in $id';
	}

	static function byId(tree:LayoutTree, at:haxe.Int64, id:String):haxe.Int64 {
		var found = find(tree, at, id);
		if (found == null)
			throw 'no element with id $id';
		return found;
	}

	static function find(tree:LayoutTree, at:haxe.Int64, id:String):Null<haxe.Int64> {
		var identity = ashui.css.Identity.of(tree, at);
		if (identity != null && identity.id == id)
			return at;
		for (child in tree.children(at)) {
			var found = find(tree, child, id);
			if (found != null)
				return found;
		}
		return null;
	}
}
