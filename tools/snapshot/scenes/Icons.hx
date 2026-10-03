import ashui.core.render.Snapshot;
import ashui.svg.SvgDocument;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.ui.Hxx.hxx;

/**
	SVG: line icons drawn in currentColor and tinted by classes, a filled
	multicolour badge with group opacity and a transform, one from Haxe
	inline markup, and an icon under a 2.25x zoom. Rendered at one and two
	image pixels per layout unit.
**/
class Icons {
	static function main() {
		ThemeState.init(DefaultTheme.bundle(), Light);
		var page = ThemeState.get().color(Background);
		var heart = SvgDocument.of(<svg viewBox="0 0 24 24"><path fill="currentColor" d="M12 21s-7.5-4.6-9.6-9.2C.9 8.4 3 4.5 6.8 4.5c2.1 0 3.6 1.1 5.2 3 1.6-1.9 3.1-3 5.2-3 3.8 0 5.9 3.9 4.4 7.3C19.5 16.4 12 21 12 21z"/></svg>);
		var build = () -> hxx('
			<div class="flex flex-row items-center p-6 gap-6" width={560} height={140}>
				<svg class="w-6 h-6 text-text-primary" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
					<polyline points="20 6 9 17 4 12" />
				</svg>
				<svg class="w-8 h-8 text-primary" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round">
					<circle cx="11" cy="11" r="7" />
					<line x1="21" y1="21" x2="16.65" y2="16.65" />
				</svg>
				<svg width="48" height="48" viewBox="0 0 48 48">
					<rect width="48" height="48" rx="12" fill="#2563eb" />
					<g opacity="0.6" transform="rotate(45 24 24)">
						<rect x="14" y="14" width="20" height="20" fill="#fbbf24" />
						<rect x="20" y="20" width="20" height="20" fill="#f43f5e" />
					</g>
					<circle cx="24" cy="24" r="5" fill="white" />
				</svg>
				${new ashui.ui.Svg(heart, {width: 32, height: 32, color: ashui.theme.Themed.color(ashui.theme.ColorToken.Error)})}
				<div class="scale-150 ml-6"><div class="scale-150">
					<svg class="w-6 h-6 text-success" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
						<path d="M22 11.08V12a10 10 0 1 1-5.93-9.14" />
						<polyline points="22 4 12 14.01 9 11.01" />
					</svg>
				</div></div>
			</div>
		');
		Snapshot.scene("icons", 560, 140, build, page.rgb(), page.a);
		Snapshot.scene("icons@2x", 560, 140, build, page.rgb(), page.a, 2.0);
	}
}
