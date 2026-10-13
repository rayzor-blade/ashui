import ashui.components.Checkbox;
import ashui.components.Input;
import ashui.components.Progress;
import ashui.components.RadioGroup;
import ashui.components.Select;
import ashui.components.Size;
import ashui.components.ToggleSwitch;
import ashui.debug.MotionRecorder;
import ashui.reactive.Signal;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Style;

/**
	The form components' motion: a field focused (its ring grows out), a
	checkbox checked (its mark pops in), a radio chosen (its dot grows), a
	progress bar moved on (its bar eases), a select opened and an item
	chosen, and inline switch icons faded and rotated in all three sizes
	(26f6deb). Writes `.ashui/snapshots/motion/forms/`.
**/
class FormMotion {
	static function main() {
		var light = Sys.getEnv("SCHEME") == "light";
		ThemeState.init(DefaultTheme.bundle(), light ? Light : Dark);
		var page = ThemeState.get().color(Background);
		var done = Signal.make(25.0);
		var size = Signal.make("small");
		var fruit = Signal.make("");
		var appearance = Signal.make(false);
		var build = () ->
			<div flexDirection={Column} padding={32} gap={20} width={720} height={460}>
				<input id="name" placeholder="Enter username" />
				<checkbox id="terms">Accept terms</checkbox>
				<div class="flex-row items-center gap-4">
					<text>Appearance</text>
					<for {density in [Size.Sm, Size.Md, Size.Lg]}>
						<toggle-switch id={"appearance-" + density} size={density} checked={appearance}>
							<svg class="ui-switch-icon-off" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20.9 13a9 9 0 0 1-9.9-9.9A9 9 0 1 0 20.9 13z" /></svg>
							<svg class="ui-switch-icon-on" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="4" /><path d="M12 2v2m0 16v2M2 12h2m16 0h2M5 5l1.5 1.5m11 11L19 19M5 19l1.5-1.5m11-11L19 5" /></svg>
						</toggle-switch>
					</for>
				</div>
				<radio-group value={size} orientation="horizontal">
					<radio-group-item value="small">Small</radio-group-item>
					<radio-group-item id="large" value="large">Large</radio-group-item>
				</radio-group>
				<progress value={done} max={100} />
				<select id="fruit" value={fruit} placeholder="Choose a fruit...">
					<select-item value="apple">Apple</select-item><select-item value="banana">Banana</select-item>
				</select>
			</div>
		;
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
		var result = MotionRecorder.record(light ? "forms-light" : "forms", 720, 460, build, {
			fps: 60,
			frames: 140,
			minFrames: 125,
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
					var p = at(tree, "appearance-lg");
					click(tree, p.x, p.y);
				case 70:
					var p = at(tree, "fruit");
					click(tree, p.x, p.y);
				case 88:
					// The list's second row, under the select.
					var p = at(tree, "fruit");
					click(tree, p.x, p.y + 20 + 36 + 18);
				case 105: appearance.set(false);
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
