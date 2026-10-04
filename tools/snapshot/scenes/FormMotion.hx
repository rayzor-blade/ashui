import ashui.components.Checkbox;
import ashui.components.Input;
import ashui.components.Progress;
import ashui.components.RadioGroup;
import ashui.components.Select;
import ashui.debug.MotionRecorder;
import ashui.reactive.Signal;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Style;
import ashui.ui.Hxx.hxx;

/**
	The form components' motion: a field focused (its ring grows out), a
	checkbox checked (its mark pops in), a radio chosen (its dot grows), a
	progress bar moved on (its bar eases), a select opened and an item
	chosen. Writes `.ashui/snapshots/motion/forms/`.
**/
class FormMotion {
	static function main() {
		ThemeState.init(DefaultTheme.bundle(), Dark);
		var page = ThemeState.get().color(Background);
		var done = Signal.make(25.0);
		var size = Signal.make("small");
		var fruit = Signal.make("");
		var build = () -> hxx('
			<div flexDirection={Column} padding={32} gap={20} width={720} height={460}>
				<input id="name" placeholder="Enter username" />
				<checkbox id="terms">Accept terms</checkbox>
				<radio-group value={size} orientation="horizontal">
					<radio-group-item value="small">Small</radio-group-item>
					<radio-group-item id="large" value="large">Large</radio-group-item>
				</radio-group>
				<progress value={done} max={100} />
				<select id="fruit" value={fruit} placeholder="Choose a fruit...">
					<select-item value="apple">Apple</select-item><select-item value="banana">Banana</select-item>
				</select>
			</div>
		');
		function at(tree:ashui.layout.LayoutTree, id:String):{x:Float, y:Float} {
			var node = byId(tree, tree.root.id, id);
			if (node == null)
				throw 'no element #$id';
			var b = tree.getBounds(new ashui.layout.Node(node));
			return {x: b.x + b.width / 2, y: b.y + b.height / 2};
		}
		function click(tree:ashui.layout.LayoutTree, x:Float, y:Float) {
			ashui.input.Pointer.move(tree, x, y);
			ashui.input.Pointer.press(tree);
			ashui.input.Pointer.release(tree);
		}
		var result = MotionRecorder.record("forms", 720, 460, build, {
			fps: 60,
			frames: 120,
			minFrames: 100,
			settle: 0.3,
			clear: page.rgb(),
			before: (frame, tree, root) -> switch frame {
				case 1:
					var p = at(tree, "name");
					click(tree, p.x, p.y);
				case 16:
					var p = at(tree, "terms");
					click(tree, p.x, p.y);
				case 31:
					var p = at(tree, "large");
					click(tree, p.x, p.y);
				case 46:
					done.set(80);
				case 70:
					var p = at(tree, "fruit");
					click(tree, p.x, p.y);
				case 88:
					// The list's second row, under the select.
					var p = at(tree, "fruit");
					click(tree, p.x, p.y + 20 + 36 + 18);
				case _:
			}
		});
		Sys.println(result.report);
		Sys.println('size ${size.get()} fruit ${fruit.get()}');
	}

	static function byId(tree:ashui.layout.LayoutTree, at:haxe.Int64, id:String):Null<haxe.Int64> {
		var identity = ashui.css.Identity.of(tree, at);
		if (identity != null && identity.id == id)
			return at;
		for (child in tree.children(at)) {
			var found = byId(tree, child, id);
			if (found != null)
				return found;
		}
		return null;
	}
}
