import ashui.core.render.Snapshot;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Style;
import ashui.ui.Div;
import ashui.ui.Hxx.hxx;

/** Gradient classes: each direction kind, a middle stop and its position, radial, and a lone from-. **/
class Gradients {
	static function main() {
		ThemeState.init(DefaultTheme.bundle(), Light);
		var page = ThemeState.get().color(Background);
		Snapshot.scene("gradients", 560, 120, () -> hxx('
			<div class="flex flex-row p-4 gap-4" width={560} height={120}>
				<div class="w-24 h-20 rounded-lg bg-linear-to-r from-primary to-info" />
				<div class="w-24 h-20 rounded-lg bg-gradient-to-br from-primary via-accent to-success" />
				<div class="w-24 h-20 rounded-lg bg-linear-to-t from-error via-warning via-20% to-success" />
				<div class="w-24 h-20 rounded-lg bg-radial from-accent to-surface-overlay" />
				<div class="w-24 h-20 rounded-lg bg-linear-to-r from-primary border border-border" />
			</div>
		'), page.rgb(), page.a);
	}
}
