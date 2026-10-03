import ashui.core.render.Snapshot;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.ui.Hxx.hxx;

/**
	Text: sizes and weights, alignment in a wider box, a wrapped paragraph,
	text under rotation and under a 2.25x zoom, and an emoji. Rendered at one
	and two image pixels per layout unit.
**/
class Text {
	static function main() {
		ThemeState.init(DefaultTheme.bundle(), Light);
		var page = ThemeState.get().color(Background);
		var build = () -> hxx('
			<div class="flex flex-col p-6 gap-3" width={560} height={360}>
				<text class="text-xs text-text-primary">Extra small, twelve pixels: the quick brown fox</text>
				<text class="text-base text-text-primary">Base size, sixteen pixels: the quick brown fox</text>
				<text class="text-2xl font-bold text-primary">Bold heading 2xl</text>
				<div class="w-full bg-surface rounded-lg p-2">
					<text class="text-sm text-center text-text-primary w-full">Centred in a wider box</text>
				</div>
				<div width={256}><text class="text-sm text-text-secondary">A paragraph that wraps inside a box 256 pixels wide, so it takes a few lines.</text></div>
				<div class="flex flex-row gap-12 items-center h-16">
					<div class="rotate-12"><text class="text-base text-text-primary">Rotated</text></div>
					<div class="scale-150 ml-8"><div class="scale-150"><text class="text-xs text-error">Zoomed</text></div></div>
					<text class="text-xl">Emoji 🎉</text>
				</div>
			</div>
		');
		Snapshot.scene("text", 560, 360, build, page.rgb(), page.a);
		Snapshot.scene("text@2x", 560, 360, build, page.rgb(), page.a, 2.0);
	}
}
