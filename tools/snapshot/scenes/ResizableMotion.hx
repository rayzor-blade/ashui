import ashui.components.Resizable;
import ashui.debug.MotionRecorder;
import ashui.reactive.Signal;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Style;
import ashui.ui.Hxx.hxx;

/**
	Resizable panels: the first handle dragged right and back past its
	panel's bounds, the second stepped by its arrow keys, and the bottom
	panel of a column dragged up. Writes `.ashui/snapshots/motion/resizable/`
	(`resizable-light` with `SCHEME=light`; `PLAIN=1` leaves the overlay out).
**/
class ResizableMotion {
	static function key(k:window.Key, code:window.KeyCode):window.KeyEvent
		return Input(Code(code), k, None, Standard, Pressed, false, Unavailable);

	static function main() {
		var light = Sys.getEnv("SCHEME") == "light";
		var plain = Sys.getEnv("PLAIN") != null;
		ThemeState.init(DefaultTheme.bundle(), light ? Light : Dark);
		var page = ThemeState.get().color(Background);
		var left = Signal.make(200.0), right = Signal.make(140.0), bottom = Signal.make(110.0);
		ashui.css.Css.load('
			.ui-resizable-panel { align-items: center; justify-content: center; gap: 8px; }
			.ui-resizable-panel p { font-size: 13px; color: var(--text-primary); }
			.ui-resizable-panel small { font-size: 11px; color: var(--text-tertiary); }
			.center { background: var(--surface-elevated); }
		');
		var build = () -> hxx('
			<div flexDirection={Column} padding={24} gap={20} width={760} height={560}>
				<resizable grip={true} height={220}>
					<resizable-panel size={left} minSize={100} maxSize={400}><p>Left Panel</p><small>Min 100, max 400</small></resizable-panel>
					<resizable-panel id="center"><p>Center Panel</p><small>Grows to fill the space</small></resizable-panel>
					<resizable-panel size={right} minSize={100}><p>Right</p><small>Min 100</small></resizable-panel>
				</resizable>
				<resizable direction="vertical" height={260}>
					<resizable-panel><p>Main Content Area</p></resizable-panel>
					<resizable-panel size={bottom} minSize={60} maxSize={200}><p>Bottom Panel</p><small>Min 60, max 200</small></resizable-panel>
				</resizable>
			</div>
		');
		ashui.css.Css.load('#center { background: var(--surface-elevated); }');
		var handles:Array<haxe.Int64> = [];
		var hx = 0.0, hy = 0.0;
		var result = MotionRecorder.record((light ? "resizable-light" : "resizable") + (plain ? "-plain" : ""), 760, 560, build, {
			fps: 60,
			frames: 110,
			minFrames: 100,
			clear: page.rgb(),
			overlay: !plain,
			thumbs: 12,
			before: (frame, tree, root) -> {
				if (handles.length == 0)
					handles = [for (id in tree.order()) if (ashui.css.Identity.of(tree, id) != null && ashui.css.Identity.of(tree, id).hasClass("ui-resizable-handle")) id];
				function centre(i:Int) {
					var b = tree.getBounds(new ashui.layout.Node(handles[i]));
					return {x: b.x + b.width / 2, y: b.y + b.height / 2};
				}
				switch frame {
					case 1:
						var c = centre(0);
						hx = c.x;
						hy = c.y;
						ashui.input.Pointer.move(tree, hx, hy);
					case 12:
						ashui.input.Pointer.press(tree);
					case f if (f > 12 && f <= 32):
						// Right, past the max of 400.
						ashui.input.Pointer.move(tree, hx + (f - 12) * 12, hy);
					case f if (f > 32 && f <= 48):
						// Back left, past the min of 100.
						ashui.input.Pointer.move(tree, hx + 240 - (f - 32) * 22, hy);
					case 50:
						ashui.input.Pointer.release(tree);
					case 56:
						var c = centre(1);
						ashui.input.Pointer.move(tree, c.x, c.y + 60);
						ashui.input.Pointer.press(tree);
						ashui.input.Pointer.release(tree);
					case 58 | 62 | 66:
						ashui.input.Keyboard.input(tree, key(Named(ArrowLeft), ArrowLeft));
					case 72:
						var c = centre(2);
						hx = c.x;
						hy = c.y;
						ashui.input.Pointer.move(tree, hx, hy);
						ashui.input.Pointer.press(tree);
					case f if (f > 72 && f <= 88):
						ashui.input.Pointer.move(tree, hx, hy - (f - 72) * 4);
					case 90:
						ashui.input.Pointer.release(tree);
						ashui.input.Pointer.move(tree, 740, 540);
					case _:
				}
			}
		});
		Sys.println(result.report.split("\n")[0]);
		Sys.println('left ${left.get()} right ${right.get()} bottom ${bottom.get()}');
	}
}
