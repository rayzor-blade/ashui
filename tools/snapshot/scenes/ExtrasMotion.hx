import ashui.components.AspectRatio;
import ashui.components.Avatar;
import ashui.components.AvatarGroup;
import ashui.components.InputOtp;
import ashui.debug.MotionRecorder;
import ashui.reactive.Signal;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Style;
import ashui.ui.Hxx.hxx;

/**
	Aspect ratios, avatar groups and a one-time code typed in, recorded
	with the motion overlay. Writes `.ashui/snapshots/motion/extras/`
	(`PLAIN=1` leaves the overlay out).
**/
class ExtrasMotion {
	static function main() {
		var plain = Sys.getEnv("PLAIN") != null;
		ThemeState.init(DefaultTheme.bundle(), Dark);
		var page = ThemeState.get().color(Background);
		var code = Signal.make("");
		var done = Signal.make("");
		ashui.css.Css.load('.ui-aspect-ratio > div { background: var(--surface-elevated); align-items: center; justify-content: center; }');
		var build = () -> hxx('
			<div flexDirection={Column} padding={32} gap={28} width={760} height={420}>
				<div flexDirection={Row} gap={16} alignItems={End}>
					<div width={80}><aspect-ratio ratio={1}><div><p>1:1</p></div></aspect-ratio></div>
					<div width={140}><aspect-ratio><div><p>16:9</p></div></aspect-ratio></div>
					<div width={100}><aspect-ratio ratio={4 / 3}><div><p>4:3</p></div></aspect-ratio></div>
					<div width={180}><aspect-ratio ratio={21 / 9}><div><p>21:9</p></div></aspect-ratio></div>
					<div width={50}><aspect-ratio ratio={9 / 16}><div><p>9:16</p></div></aspect-ratio></div>
				</div>
				<div flexDirection={Row} gap={40} alignItems={Center}>
					<avatar-group><avatar><avatar-fallback>AL</avatar-fallback></avatar><avatar><avatar-fallback>BO</avatar-fallback></avatar><avatar><avatar-fallback>CY</avatar-fallback></avatar></avatar-group>
					<avatar-group max={3}><avatar><avatar-fallback>AL</avatar-fallback></avatar><avatar><avatar-fallback>BO</avatar-fallback></avatar><avatar><avatar-fallback>CY</avatar-fallback></avatar><avatar><avatar-fallback>DI</avatar-fallback></avatar><avatar><avatar-fallback>EV</avatar-fallback></avatar></avatar-group>
				</div>
				<input-otp id="otp" value={code} separator={3} onComplete={c -> done.set(c)} />
			</div>
		');
		var result = MotionRecorder.record("extras" + (plain ? "-plain" : ""), 760, 420, build, {
			fps: 60,
			frames: 60,
			minFrames: 50,
			clear: page.rgb(),
			overlay: !plain,
			before: (frame, tree, root) -> switch frame {
				case 1:
					var otp = [for (id in tree.order()) if (ashui.css.Identity.of(tree, id) != null && ashui.css.Identity.of(tree, id).hasClass("ui-input-otp")) id][0];
					var b = tree.getBounds(new ashui.layout.Node(otp));
					ashui.input.Pointer.move(tree, b.x + 20, b.y + b.height / 2);
					ashui.input.Pointer.press(tree);
					ashui.input.Pointer.release(tree);
				case 10: ashui.input.Keyboard.text(tree, "12");
				case 20: ashui.input.Keyboard.text(tree, "34a5");
				case 30: ashui.input.Keyboard.text(tree, "6");
				case _:
			}
		});
		Sys.println(result.report.split("\n")[0]);
		Sys.println('code ${code.get()} done ${done.get()}');
	}
}
