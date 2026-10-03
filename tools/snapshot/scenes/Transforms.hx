import ashui.core.render.Snapshot;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Style;
import ashui.ui.Div;
import ashui.ui.Hxx.hxx;

/** Transform classes: a turn with its shadow, a slant, a shrink, and a turned parent clipping its child. **/
class Transforms {
	static function main() {
		ThemeState.init(DefaultTheme.bundle(), Light);
		var page = ThemeState.get().color(Background);
		Snapshot.scene("transforms", 560, 160, () -> hxx('
			<div class="flex flex-row items-center p-6 gap-8" width={560} height={160}>
				<div class="w-20 h-20 shrink-0 rounded-xl bg-primary shadow-lg rotate-12" />
				<div class="w-20 h-20 shrink-0 rounded-xl bg-success border-2 border-border skew-x-12" />
				<div class="w-20 h-20 shrink-0 rounded-xl bg-warning scale-75" />
				<div class="w-24 h-24 shrink-0 rounded-2xl bg-surface border border-border overflow-hidden -rotate-6">
					<div class="w-32 h-12 bg-linear-to-r from-error to-accent" />
				</div>
			</div>
		'), page.rgb(), page.a);
	}
}
