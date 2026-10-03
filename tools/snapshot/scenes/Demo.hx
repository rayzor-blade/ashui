import ashui.core.render.Snapshot;
import ashui.theme.ColorScheme;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Brush;
import ashui.types.Style;
import ashui.ui.Div;
import ashui.ui.Hxx.hxx;

/**
	A card in the default theme, light and dark: surface, border and shadow
	from the theme's tokens, corners on its radius ladder, so the larger
	ones take the theme's squircle and the pills stay round.
**/
class Demo {
	static function main() {
		ThemeState.init(DefaultTheme.bundle(), Light);
		var theme = ThemeState.get();
		for (scheme in [ColorScheme.Light, ColorScheme.Dark]) {
			theme.setScheme(scheme);
			var page = theme.color(Background);
			Snapshot.scene(scheme == Light ? "demo-light" : "demo-dark", 320, 200, card, page.rgb(), page.a);
		}
	}

	static function card():Div {
		var theme = ThemeState.get();
		var primary = theme.color(Primary).rgb();
		var accent = theme.color(Accent).rgb();
		return hxx('
			<div class="items-center justify-center" width={320} height={200}>
				<div class="flex flex-col p-4 gap-3 bg-surface border border-border rounded-xl shadow-lg" width={280} height={160}>
					<div class="h-14 shrink-0 rounded-lg" bg={Brush.linearGradient(0, 0, 248, 0, primary, 1, accent, 0.6)} />
					<div class="flex flex-row gap-2">
						<div class="w-16 h-6 rounded-full bg-accent-subtle" />
						<div class="w-12 h-6 rounded-full bg-success-bg" />
						<div class="w-16 h-6 rounded-full corner-squircle rounded-md bg-warning-bg" />
					</div>
				</div>
			</div>
		');
	}
}
