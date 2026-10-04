import ashui.components.Button;
import ashui.components.Card;
import ashui.components.Drawer;
import ashui.debug.MotionRecorder;
import ashui.reactive.Signal;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Style;
import ashui.ui.Hxx.hxx;

/**
	Drawers over a page: one from the bottom opened, pulled a little and let
	go so it springs back, then pulled past a third and let go so it closes
	from there; then a navigation drawer from the left, opened and flicked
	shut. Writes `.ashui/snapshots/motion/drawer/` (`drawer-light` with
	`SCHEME=light`; `PLAIN=1` leaves the overlay out).
**/
class DrawerMotion {
	static function main() {
		var light = Sys.getEnv("SCHEME") == "light";
		var plain = Sys.getEnv("PLAIN") != null;
		ThemeState.init(DefaultTheme.bundle(), light ? Light : Dark);
		var page = ThemeState.get().color(Background);
		var goal = Signal.make(350);
		var goalText = ashui.reactive.Computed.make(() -> Std.string(goal.get()));
		ashui.css.Css.load('
			#page > p { font-size: 14px; color: var(--text-secondary); }
			#page > h2 { font-size: 22px; font-weight: 600; color: var(--text-primary); }
			#goal { flex-direction: row; align-items: center; justify-content: center; gap: 24px; padding: 8px 0; }
			#goalValue { flex-direction: column; align-items: center; gap: 2px; width: 140px; }
			#goalValue > h1 { font-size: 56px; font-weight: 700; color: var(--text-primary); margin: 0; }
			#goalValue > small { font-size: 11px; color: var(--text-tertiary); }
			#nav { flex-direction: column; gap: 2px; margin: 0 8px; }
			#nav > .ui-button { justify-content: flex-start; }
		');
		var build = () -> hxx('
			<div id="page" flexDirection={Column} padding={32} gap={20} width={900} height={600}>
				<h2>Activity</h2>
				<p>Track your daily movement and set goals that stretch you.</p>
				<div flexDirection={Row} gap={16}>
					<card width={260} height={140}><card-header><card-title>Steps</card-title><card-description>8,240 today</card-description></card-header></card>
					<card width={260} height={140}><card-header><card-title>Calories</card-title><card-description>312 of 350</card-description></card-header></card>
					<card width={260} height={140}><card-header><card-title>Stand</card-title><card-description>9 of 12 hours</card-description></card-header></card>
				</div>
				<div flexDirection={Row} gap={12}>
					<drawer>
						<drawer-trigger id="openGoal" variant={Outline}>Set Goal</drawer-trigger>
						<drawer-content>
							<drawer-header><drawer-title>Move Goal</drawer-title><drawer-description>Set your daily activity goal.</drawer-description></drawer-header>
							<div id="goal">
								<button variant={Outline} size={Icon} onClick={_ -> goal.set(goal.get() - 10)}>-</button>
								<div id="goalValue"><h1>{goalText}</h1><small>CALORIES/DAY</small></div>
								<button variant={Outline} size={Icon} onClick={_ -> goal.set(goal.get() + 10)}>+</button>
							</div>
							<drawer-footer><button>Submit</button><drawer-close>Cancel</drawer-close></drawer-footer>
						</drawer-content>
					</drawer>
					<drawer>
						<drawer-trigger id="openNav" variant={Outline}>Navigation</drawer-trigger>
						<drawer-content side="left">
							<drawer-header><drawer-title>Acme</drawer-title><drawer-description>Workspace</drawer-description></drawer-header>
							<div id="nav">
								<button variant={Ghost}>Dashboard</button>
								<button variant={Ghost}>Activity</button>
								<button variant={Ghost}>Goals</button>
								<button variant={Ghost}>Settings</button>
							</div>
						</drawer-content>
					</drawer>
				</div>
			</div>
		');
		function find(tree:ashui.layout.LayoutTree, cls:String):Null<ashui.layout.Node> {
			for (id in tree.order()) {
				var i = ashui.css.Identity.of(tree, id);
				if (i != null && (i.hasClass(cls) || i.id == cls) && tree.getBounds(new ashui.layout.Node(id)) != null)
					return new ashui.layout.Node(id);
			}
			return null;
		}
		var hx = 0.0, hy = 0.0;
		var result = MotionRecorder.record((light ? "drawer-light" : "drawer") + (plain ? "-plain" : ""), 900, 600, build, {
			fps: 60,
			frames: 200,
			minFrames: 190,
			clear: page.rgb(),
			overlay: !plain,
			thumbs: 15,
			before: (frame, tree, root) -> {
				function press(n:ashui.layout.Node) {
					var b = tree.getBounds(n);
					ashui.input.Pointer.move(tree, b.x + b.width / 2, b.y + b.height / 2);
					ashui.input.Pointer.press(tree);
					ashui.input.Pointer.release(tree);
				}
				function grab(cls:String) {
					var b = tree.getBounds(find(tree, cls));
					hx = b.x + b.width / 2;
					hy = b.y + b.height / 2;
					ashui.input.Pointer.move(tree, hx, hy);
					ashui.input.Pointer.press(tree);
				}
				switch frame {
					case 2: press(find(tree, "openGoal"));
					// Pulled down a little and let go: it springs back.
					case 40: grab("ui-drawer-handle");
					case f if (f > 40 && f <= 52): ashui.input.Pointer.move(tree, hx, hy + (f - 40) * 5);
					case 53: ashui.input.Pointer.release(tree);
					// Pulled past a third and let go: it closes from there.
					case 90: grab("ui-drawer-handle");
					case f if (f > 90 && f <= 104): ashui.input.Pointer.move(tree, hx, hy + (f - 90) * 9);
					case 105: ashui.input.Pointer.release(tree);
					case 125: press(find(tree, "openNav"));
					// A flick toward its edge closes it, though it went only a little way.
					case 165: grab("ui-dialog-header");
					case f if (f > 165 && f <= 168): ashui.input.Pointer.move(tree, hx - (f - 165) * 16, hy);
					case 169: ashui.input.Pointer.release(tree);
					case _:
				}
			}
		});
		Sys.println(result.report.split("\n")[0]);
	}
}
