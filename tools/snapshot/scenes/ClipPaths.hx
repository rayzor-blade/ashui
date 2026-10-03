import ashui.core.render.Snapshot;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.ui.Hxx.hxx;

/**
	Clip paths from Tailwind classes: gradient tiles holding a line of text,
	each clipped by a `[clip-path:…]` class, which clips the tile and its
	text alike. A circle and an ellipse, a rounded inset, a triangle and a
	star from points (solid, by CSS's nonzero rule, though its edges cross),
	a chevron and a frame from path data, its hole wound the other way
	round, and an ellipse on a turned tile. Rendered at one and two image
	pixels per layout unit.
**/
class ClipPaths {
	static function main() {
		ThemeState.init(DefaultTheme.bundle(), Light);
		var page = ThemeState.get().color(Background);
		var build = () -> hxx('
			<div class="flex flex-row flex-wrap items-start p-6 gap-6" width={600} height={300}>
				<div class="flex flex-col items-center gap-2">
					<div class="flex items-center justify-center w-24 h-24 bg-linear-to-br from-primary to-success [clip-path:circle()]">
						<text class="text-sm font-bold text-text-inverse">circle</text>
					</div>
					<text class="text-xs text-text-secondary">circle()</text>
				</div>
				<div class="flex flex-col items-center gap-2">
					<div class="flex items-center justify-center w-24 h-24 bg-linear-to-br from-primary to-success [clip-path:ellipse(50%_30%)]">
						<text class="text-sm font-bold text-text-inverse">ellipse</text>
					</div>
					<text class="text-xs text-text-secondary">ellipse(50% 30%)</text>
				</div>
				<div class="flex flex-col items-center gap-2">
					<div class="flex items-center justify-center w-24 h-24 bg-linear-to-br from-primary to-success [clip-path:inset(12px_round_16px)]">
						<text class="text-sm font-bold text-text-inverse">inset</text>
					</div>
					<text class="text-xs text-text-secondary">inset(12px round 16px)</text>
				</div>
				<div class="flex flex-col items-center gap-2">
					<div class="flex items-center justify-center w-24 h-24 bg-linear-to-br from-primary to-success [clip-path:polygon(50%_0,100%_100%,0_100%)]">
						<text class="text-sm font-bold text-text-inverse">triangle</text>
					</div>
					<text class="text-xs text-text-secondary">polygon(…)</text>
				</div>
				<div class="flex flex-col items-center gap-2">
					<div class="flex items-center justify-center w-24 h-24 bg-linear-to-br from-primary to-success [clip-path:polygon(50%_0,79.4%_90.5%,2.4%_34.5%,97.6%_34.5%,20.6%_90.5%)]">
						<text class="text-sm font-bold text-text-inverse">star</text>
					</div>
					<text class="text-xs text-text-secondary">polygon(…)</text>
				</div>
				<div class="flex flex-col items-center gap-2">
					<div class="flex items-center justify-center w-24 h-24 bg-linear-to-br from-primary to-success [clip-path:path(\'M0_24_L48_72_L96_24_L96_48_L48_96_L0_48_Z\')]" />
					<text class="text-xs text-text-secondary">path(…)</text>
				</div>
				<div class="flex flex-col items-center gap-2">
					<div class="flex items-center justify-center w-24 h-24 bg-linear-to-br from-primary to-success [clip-path:path(\'M8_8_H88_V88_H8_Z_M28_28_V68_H68_V28_Z\')]" />
					<text class="text-xs text-text-secondary">path(…), a hole</text>
				</div>
				<div class="flex flex-col items-center gap-2">
					<div class="flex items-center justify-center w-24 h-24 rotate-45 bg-linear-to-br from-primary to-success [clip-path:ellipse(50%_25%)]">
						<text class="text-sm font-bold text-text-inverse">turned</text>
					</div>
					<text class="text-xs text-text-secondary">rotate-45</text>
				</div>
			</div>
		');
		Snapshot.scene("clip-paths", 600, 300, build, page.rgb(), page.a);
		Snapshot.scene("clip-paths@2x", 600, 300, build, page.rgb(), page.a, 2.0);
	}
}
