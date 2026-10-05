import ashui.core.render.Snapshot;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Style;

/**
	Text in faces the primary face lacks glyphs for, from Blinc's fallback
	faces: Chinese, Japanese and Korean, symbols and emoji, beside Latin, in
	the system face, monospace, serif and bold. Writes
	`.ashui/snapshots/fallback-text.png`.
**/
class FallbackText {
	static function main() {
		ThemeState.init(DefaultTheme.bundle(), Dark);
		var page = ThemeState.get().color(Background);
		var line = "Hello 你好 こんにちは 안녕 ★ ✓ 😀😀";
		var build = () -> <div flexDirection={Column} padding={24} gap={16} width={640}>
			<text class="text-lg">{line}</text>
			<text class="text-lg font-mono">{line}</text>
			<text class="text-lg font-serif">{line}</text>
			<text class="text-lg font-bold">{line}</text>
		</div>;
		Snapshot.scene("fallback-text", 640, 260, build, page.rgb(), page.a, 2.0, 1.0);
	}
}
