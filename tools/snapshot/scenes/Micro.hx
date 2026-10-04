import ashui.core.render.Snapshot;
import ashui.reactive.Signal;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Style;
import ashui.ui.Hxx.hxx;

/**
	Micro motion on the theme's tokens, at 60 frames a second: frame 0 at
	rest; at frame 1 the text input takes focus, its ring growing out, the
	checkbox is checked, its mark scaling in, and a dialog opens, growing in
	over its fading backdrop.
**/
class Micro {
	static function main() {
		ThemeState.init(DefaultTheme.bundle(), Light);
		var page = ThemeState.get().color(Background);
		var agreed = Signal.make(false);
		var open = Signal.make(false);
		var field:Null<ashui.ui.Input> = null;
		var build = () -> {
			field = new ashui.ui.Input({type: "text", placeholder: "Focus grows a ring"});
			hxx('
				<div flexDirection={Column} alignItems={Start} padding={24} gap={16} width={360} height={260}>
					{field}
					<label><input type="checkbox" checked={agreed} />Checked as it scales in</label>
					<dialog open={open}><h3>Grows in</h3><p>From nothing, on the sheet curve.</p></dialog>
				</div>
			');
		};
		Snapshot.sequence("micro", 360, 260, build, 60, 16, (frame, tree, root) -> {
			if (frame == 1) {
				ashui.input.Focus.set(@:privateAccess field.interaction, true);
				agreed.set(true);
				open.set(true);
			}
		}, page.rgb(), page.a, 2.0);
		for (p in ashui.css.Css.problems)
			Sys.println("css: " + p);
	}
}
