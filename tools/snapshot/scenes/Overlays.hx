import ashui.core.render.Snapshot;
import ashui.reactive.Signal;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Style;
import ashui.ui.Hxx.hxx;

/**
	The top layer: frame 0 is the page; frame 1 has the select's list of
	options open below it, over the text after it; frame 2 a modal dialog,
	centred over the dimmed page. An open details sits beside them.
**/
class Overlays {
	static function main() {
		ThemeState.init(DefaultTheme.bundle(), Light);
		var page = ThemeState.get().color(Background);
		var fruit = Signal.make("pear");
		var dialogOpen = Signal.make(false);
		var select:Null<ashui.ui.Select> = null;
		var build = () -> {
			select = new ashui.ui.Select({value: fruit}, [
				new ashui.ui.Option({value: "apple"}, [new ashui.ui.Text("Apple")]),
				new ashui.ui.Option({value: "pear"}, [new ashui.ui.Text("Pear")]),
				new ashui.ui.Optgroup({label: "Citrus"}, [
					new ashui.ui.Option({value: "lemon", disabled: true}, [new ashui.ui.Text("Lemon")]),
					new ashui.ui.Option({value: "lime"}, [new ashui.ui.Text("Lime")])
				])
			]);
			hxx('
				<div flexDirection={Column} alignItems={Start} padding={24} gap={12} width={480} height={360}>
					<h3>Fruit</h3>
					{select}
					<p>Text the list of options draws over when it is open.</p>
					<details open={true}><summary>Delivery</summary><p>Tomorrow, before noon.</p></details>
					<dialog open={dialogOpen}>
						<h3>Remove the item?</h3>
						<p>It goes from your basket.</p>
						<div flexDirection={Row} gap={8}><button>Remove</button><button>Keep</button></div>
					</dialog>
				</div>
			');
		};
		Snapshot.sequence("overlays", 480, 360, build, 30, 3, (frame, tree, root) -> {
			if (frame == 1)
				@:privateAccess select.show();
			if (frame == 2) {
				@:privateAccess if (select.open != null) select.open.close();
				dialogOpen.set(true);
			}
		}, page.rgb(), page.a, 2.0);
		for (p in ashui.css.Css.problems)
			Sys.println("css: " + p);
	}
}
