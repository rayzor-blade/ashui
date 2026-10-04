import ashui.components.Calendar;
import ashui.debug.MotionRecorder;
import ashui.reactive.Signal;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Style;
import ashui.ui.Hxx.hxx;

/**
	A calendar, today fixed at 4 October 2026, recorded with the motion
	overlay: the 15th chosen by a press, the arrows moving on, Page Down
	turning to November, and Enter choosing there. Writes
	`.ashui/snapshots/motion/calendar/` (`calendar-light` with
	`SCHEME=light`).
**/
class CalendarMotion {
	static function main() {
		var light = Sys.getEnv("SCHEME") == "light";
		ThemeState.init(DefaultTheme.bundle(), light ? Light : Dark);
		var page = ThemeState.get().color(Background);
		var chosen = Signal.make((null : Null<CalendarDay>));
		var build = () -> hxx('
			<div padding={32} width={380} height={400}>
				<calendar value={chosen} today={{year: 2026, month: 9, day: 4}} />
			</div>
		');
		function key(k:window.Key, code:window.KeyCode):window.KeyEvent
			return Input(Code(code), k, None, Standard, Pressed, false, Unavailable);
		var result = MotionRecorder.record(light ? "calendar-light" : "calendar", 380, 400, build, {
			fps: 60,
			frames: 80,
			minFrames: 70,
			scale: 2,
			clear: page.rgb(),
			before: (frame, tree, root) -> switch frame {
				case 1:
					// The 15th: the third full week, its Thursday.
					var days = [for (id in tree.order()) if (ashui.css.Identity.of(tree, id) != null && ashui.css.Identity.of(tree, id).hasClass("ui-calendar-day")) id];
					var b = tree.getBounds(new ashui.layout.Node(days[18]));
					ashui.input.Pointer.move(tree, b.x + b.width / 2, b.y + b.height / 2);
					ashui.input.Pointer.press(tree);
					ashui.input.Pointer.release(tree);
				case 16: ashui.input.Keyboard.input(tree, key(Named(ArrowRight), ArrowRight));
				case 26: ashui.input.Keyboard.input(tree, key(Named(ArrowDown), ArrowDown));
				case 36: ashui.input.Keyboard.input(tree, key(Named(PageDown), PageDown));
				case 46:
					ashui.input.Keyboard.input(tree, key(Named(Enter), Enter));
					ashui.input.Keyboard.input(tree, Input(Code(Enter), Named(Enter), None, Standard, Released, false, Unavailable));
				case _:
			}
		});
		Sys.println(result.report.split("\n")[0]);
		var c = chosen.get();
		Sys.println(c == null ? "none" : '${c.year}-${c.month + 1}-${c.day}');
	}
}
