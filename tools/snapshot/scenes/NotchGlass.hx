import ashui.core.render.Snapshot;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Brush;
import ashui.types.Notch;
import ashui.ui.Hxx.hxx;

/**
	Glass in notched shapes over coloured discs: a concave-top dropdown, a
	peak, a scoop, a bulge and a cut. The top row is liquid glass, its rim
	bending what is behind along the notched outline; the middle row is
	liquid with a border; the bottom row is frosted glass.
**/
class NotchGlass {
	static function main() {
		ThemeState.init(DefaultTheme.bundle(), Light);
		var page = ThemeState.get().color(Background);
		var blobs = [
			{x: -20, y: 0, r: 70, c: 0x2563eb}, {x: 100, y: 60, r: 50, c: 0xf59e0b}, {x: 190, y: -30, r: 80, c: 0xdc2626},
			{x: 300, y: 50, r: 60, c: 0x16a34a}, {x: 420, y: -10, r: 60, c: 0x9333ea}, {x: 560, y: 60, r: 70, c: 0x0891b2},
			{x: 0, y: 170, r: 60, c: 0xdb2777}, {x: 140, y: 200, r: 70, c: 0x16a34a}, {x: 280, y: 160, r: 55, c: 0x2563eb},
			{x: 400, y: 210, r: 65, c: 0xf59e0b}, {x: 540, y: 170, r: 60, c: 0xdc2626}, {x: 20, y: 330, r: 65, c: 0x0891b2},
			{x: 170, y: 350, r: 60, c: 0x9333ea}, {x: 320, y: 320, r: 70, c: 0x65a30d}, {x: 470, y: 340, r: 65, c: 0xdb2777},
		];
		var dropdown:Notch = Notch.concaveTop(18, 16);
		var peak:Notch = {topLeft: 14, topRight: 14, bottomRight: 14, bottomLeft: 14, top: Peak(28, 12)};
		var scoop:Notch = {topLeft: 20, topRight: 20, bottomRight: 20, bottomLeft: 20, top: Scoop(56, 18, 8)};
		var bulge:Notch = {topLeft: 16, topRight: 16, bottomRight: 16, bottomLeft: 16, bottom: Bulge(60, 16, 6)};
		var cut:Notch = {topLeft: 8, topRight: 8, bottomRight: 8, bottomLeft: 8, bottom: Cut(40, 16)};
		var shapes = [dropdown, peak, scoop, bulge, cut];
		var build = () -> hxx('
			<div width={680} height={460}>
				<for {b in blobs}>
					<div class="absolute rounded-full" left={b.x} top={b.y} width={b.r * 2} height={b.r * 2} bg={Brush.solid(b.c)} />
				</for>
				<div class="absolute flex flex-row gap-4" left={20} top={24}>
					<for {n in shapes}>
						<div notch={n} class="p-4 bg-glass glass-blur-2 glass-tint-white/15 glass-aberration-40" width={116} height={110} />
					</for>
				</div>
				<div class="absolute flex flex-row gap-4" left={20} top={170}>
					<for {n in shapes}>
						<div notch={n} class="p-4 border-2 border-white/60 bg-glass glass-blur-4 glass-tint-white/20 glass-aberration-40" width={116} height={110} />
					</for>
				</div>
				<div class="absolute flex flex-row gap-4" left={20} top={316}>
					<for {n in shapes}>
						<div notch={n} class="p-4 border border-white/40 bg-glass glass-frosted glass-blur-12 glass-tint-white/30" width={116} height={110} />
					</for>
				</div>
			</div>
		');
		Snapshot.scene("notch-glass@2x", 680, 460, build, page.rgb(), page.a, 2.0);
	}
}
