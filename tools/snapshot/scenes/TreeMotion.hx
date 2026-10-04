import ashui.components.TreeView;
import ashui.debug.MotionRecorder;
import ashui.reactive.Signal;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Style;
import ashui.ui.Hxx.hxx;

/**
	A file tree: a folder opened by a press, its files growing in and the
	rows below moving down; the arrows walking into it and Enter choosing a
	file; Left stepping out and closing it; then another folder closed.
	Writes `.ashui/snapshots/motion/tree/` (`tree-light` with
	`SCHEME=light`; `PLAIN=1` leaves the overlay out).
**/
class TreeMotion {
	static final FOLDER = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z"/></svg>';
	static final FILE = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z"/><path d="M14 2v4a2 2 0 0 0 2 2h4"/></svg>';

	static function key(k:window.Key, code:window.KeyCode):window.KeyEvent
		return Input(Code(code), k, None, Standard, Pressed, false, Unavailable);

	static function main() {
		var light = Sys.getEnv("SCHEME") == "light";
		var plain = Sys.getEnv("PLAIN") != null;
		ThemeState.init(DefaultTheme.bundle(), light ? Light : Dark);
		var page = ThemeState.get().color(Background);
		var picked = Signal.make((null : Null<String>));
		var build = () -> hxx('
			<div padding={24} width={420} height={420} flexDirection={Column}>
				<tree-view selected={picked} width={300}>
					<tree-item value="project" label="ashui" icon={FOLDER} expanded={true}>
						<tree-item value="src" label="src" icon={FOLDER} expanded={true}>
							<tree-item value="main" label="Main.hx" icon={FILE} />
							<tree-item value="app" label="App.hx" icon={FILE} />
							<tree-item id="components" value="components" label="components" icon={FOLDER}>
								<tree-item value="button" label="Button.hx" icon={FILE} />
								<tree-item value="card" label="Card.hx" icon={FILE} />
								<tree-item value="dialog" label="Dialog.hx" icon={FILE} />
							</tree-item>
						</tree-item>
						<tree-item value="tests" label="tests" icon={FOLDER}>
							<tree-item value="smoke" label="Smoke.hx" icon={FILE} />
						</tree-item>
						<tree-item value="readme" label="README.md" icon={FILE} />
						<tree-item value="haxelib" label="haxelib.json" icon={FILE} />
					</tree-item>
				</tree-view>
			</div>
		');
		var result = MotionRecorder.record((light ? "tree-light" : "tree") + (plain ? "-plain" : ""), 420, 420, build, {
			fps: 60,
			frames: 130,
			minFrames: 120,
			clear: page.rgb(),
			overlay: !plain,
			thumbs: 12,
			before: (frame, tree, root) -> {
				function rowOf(id:String):haxe.Int64 {
					var item = Lambda.find(tree.order(), n -> ashui.css.Identity.of(tree, n) != null && ashui.css.Identity.of(tree, n).id == id);
					return tree.children(item)[0];
				}
				switch frame {
					case 4:
						var b = tree.getBounds(new ashui.layout.Node(rowOf("components")));
						ashui.input.Pointer.move(tree, b.x + 40, b.y + b.height / 2);
						ashui.input.Pointer.press(tree);
						ashui.input.Pointer.release(tree);
					case 40 | 46: ashui.input.Keyboard.input(tree, key(Named(ArrowDown), ArrowDown));
					case 52: ashui.input.Keyboard.input(tree, key(Named(Enter), Enter));
					case 62 | 72: ashui.input.Keyboard.input(tree, key(Named(ArrowLeft), ArrowLeft));
					case 100:
						ashui.input.Pointer.move(tree, 60, 54);
						ashui.input.Pointer.press(tree);
						ashui.input.Pointer.release(tree);
						ashui.input.Pointer.move(tree, 400, 400);
					case _:
				}
			}
		});
		Sys.println(result.report.split("\n")[0]);
		Sys.println('picked ${picked.get()}');
	}
}
