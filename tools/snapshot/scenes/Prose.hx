import ashui.core.render.Snapshot;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Style;
import ashui.ui.Hxx.hxx;

/**
	Text flow in a narrow column: a centred heading, a justified paragraph
	with a highlight and code that wrap onto the next line, a box on each,
	and a long address that breaks where overflow-wrap lets it.
**/
class Prose {
	static function main() {
		ThemeState.init(DefaultTheme.bundle(), Light);
		var page = ThemeState.get().color(Background);
		ashui.css.Css.load('#justified { text-align: justify } #address { overflow-wrap: anywhere }');
		var build = () -> hxx('
			<div flexDirection={Column} alignItems={Stretch} padding={24} width={300} height={420}>
				<h2 class="text-center">A centred heading</h2>
				<p id="justified">Justified text spreads each line to the edge, and a <mark>highlight that runs over a line break</mark> gets a box on each line, as does <code>some.inline.code()</code> when it wraps.</p>
				<p id="address">See https://example.com/a/very/long/address/that/would/overflow</p>
			</div>
		');
		Snapshot.scene("prose@2x", 300, 420, build, page.rgb(), page.a, 2.0);
		for (p in ashui.css.Css.problems)
			Sys.println("css: " + p);
	}
}
