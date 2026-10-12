import ashui.components.Label;
import ashui.components.NumberInput;
import ashui.components.Size;
import ashui.css.Css;
import ashui.debug.MotionRecorder;
import ashui.input.Pointer;
import ashui.layout.Node;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;

/** Centered numbers stay still while the field and steppers change hover state (git-bug d5a8df1). **/
class NumberInputMotion {
	static function main() {
		var light = Sys.getEnv("SCHEME") == "light";
		ThemeState.init(DefaultTheme.bundle(), light ? Light : Dark);
		var build = () -> <div class="bg-background flex-col p-6 gap-4" width={560} height={240}>
			<text class="text-lg font-semibold">NumberInput · hover stability</text>
			<for {size in [Size.Sm, Size.Md, Size.Lg]}>
				<div class="flex-row items-center gap-4">
					<div width={80}><label>${size == Size.Sm ? "Small" : size == Size.Md ? "Medium" : "Large"}</label></div>
					<number-input size={size} value={0.5} step={0.5} />
					<number-input size={size} value={12.5} step={0.5} />
					<number-input size={size} value={1.0} />
				</div>
			</for>
		</div>;
		var result = MotionRecorder.record(light ? "number-input-hover-light" : "number-input-hover", 560, 240, build, {
			fps: 60, frames: 80, minFrames: 80, scale: 2, settle: 0.5, overlay: false,
			clear: ThemeState.get().color(Background).rgb(),
			before: (frame, tree, root) -> {
				if (frame == 60) Pointer.leave(tree);
				else if (frame == 1 || frame == 20 || frame == 40) {
					var field = Css.query(tree, root.node.id, "input.ui-number-field")[0];
					var number = tree.ancestors(field)[0], parts = tree.children(number);
					var b = tree.getBounds(new Node(parts[frame == 1 ? 1 : frame == 20 ? 0 : 2]));
					Pointer.move(tree, b.x + b.width / 2, b.y + b.height / 2);
				}
			}
		});
		Sys.println(result.report.split("\n")[0]);
	}
}
