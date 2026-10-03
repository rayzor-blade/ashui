import ashui.core.render.Snapshot;
import ashui.reactive.Signal;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Style;
import ashui.ui.Hxx.hxx;

/**
	Built-in elements in their user-agent looks: headings and text, a
	checked, an unchecked and an indeterminate checkbox with labels, a set
	of radios with one disabled, and buttons, one disabled. Rendered at one
	and two image pixels per layout unit.
**/
class Controls {
	static function main() {
		ThemeState.init(DefaultTheme.bundle(), Light);
		var page = ThemeState.get().color(Background);
		var size = Signal.make("m");
		var build = () -> hxx('
			<div flexDirection={Column} alignItems={Start} padding={24} gap={4} width={480} height={420}>
				<h2>Built-in elements</h2>
				<p>Text from the user-agent stylesheet, with <strong>strong</strong> and <code>code</code> beside it.</p>
				<label><input type="checkbox" checked={true} />Checked</label>
				<label><input type="checkbox" />Unchecked</label>
				<label><input type="checkbox" indeterminate={true} />Indeterminate</label>
				<div flexDirection={Row} gap={16} marginTop={8}>
					<label><input type="radio" name="size" value="s" group={size} />Small</label>
					<label><input type="radio" name="size" value="m" group={size} />Medium</label>
					<label><input type="radio" name="size" value="l" group={size} disabled={true} />Large</label>
				</div>
				<div flexDirection={Row} gap={12} marginTop={12}>
					<button>Save</button>
					<button disabled={true}>Disabled</button>
				</div>
			</div>
		');
		Snapshot.scene("controls", 480, 420, build, page.rgb(), page.a);
		Snapshot.scene("controls@2x", 480, 420, build, page.rgb(), page.a, 2.0);
		for (p in ashui.css.Css.problems)
			Sys.println("css: " + p);
	}
}
