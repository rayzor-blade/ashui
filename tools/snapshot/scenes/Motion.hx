import ashui.core.render.Snapshot;
import ashui.css.Css;
import ashui.layout.Element;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.ui.Div;
import ashui.ui.Text;

/**
	Motion recorded frame by frame: twelve frames a second apart a twelfth,
	`motion-000.png` to `motion-011.png`. A dot pulses and a square turns by
	CSS animations, a bar slides out and back, and at frame 4 the card's
	class changes, so its colour and lift move by its transition. The time
	is the frames', so every run draws the same twelve.
**/
class Motion {
	static final CSS = '
		.stage { flex-direction: row; gap: 24px; padding: 24px; width: 480px; height: 160px; align-items: center; background: #f8fafc; }
		@keyframes pulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.2; } }
		@keyframes turn { to { transform: rotate(360deg); } }
		@keyframes slide { from { width: 8px } 50% { width: 96px } to { width: 8px } }
		.dot { width: 32px; height: 32px; border-radius: 9999px; background: #6366f1; animation: pulse 1s ease-in-out infinite; }
		.square { width: 32px; height: 32px; border-radius: 6px; background: #f59e0b; animation: turn 1s linear infinite; }
		.bar { height: 12px; border-radius: 6px; background: #10b981; animation: slide 1s ease-in-out infinite; }
		.card { width: 120px; height: 80px; border-radius: 12px; padding: 12px; background: #e2e8f0; color: #334155;
			transition: background 400ms ease-out, transform 400ms ease-out, box-shadow 400ms ease-out; }
		.card.lifted { background: #6366f1; color: white; transform: translateY(-8px); box-shadow: 0 12px 24px rgba(99, 102, 241, 0.4); }
	';

	static function main() {
		ThemeState.init(DefaultTheme.bundle(), Light);
		Css.load(CSS, "Motion.css");
		var card:Null<Div> = null;
		var build = () -> {
			card = new Div({classes: ashui.reactive.Signal.make(["card"])}, [new Text("Card")]);
			new Div({classes: ["stage"]}, [
				new Div({classes: ["dot"]}),
				new Div({classes: ["square"]}),
				new Div({width: 100, alignItems: ashui.types.Style.Align.Start}, [new Div({classes: ["bar"]})]),
				(card : Element)
			]);
		};
		Snapshot.sequence("motion", 480, 160, build, 12, 12, (frame, tree, root) -> {
			if (frame == 4)
				ashui.css.Identity.of(tree, card.node.id).setClasses(["card", "lifted"]);
		});
		for (p in Css.problems)
			Sys.println("css: " + p);
	}
}
