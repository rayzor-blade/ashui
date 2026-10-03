import ashui.core.render.Snapshot;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Brush;
import ashui.ui.Hxx.hxx;

/**
	Glass and blur brushes over a backdrop of coloured discs and a line of
	text, so a panel's rounded edge shows against curves. The top row blurs
	by 0, 2, 4, 8, 16 and 32, clear to heavy. The bottom row is frosted
	glass at the same blur with a white tint from none to strong, then a
	dark one. The last row is Tailwind's: a background colour at an
	opacity over a `backdrop-blur-` size, light frost to heavy. Each panel
	blurs only what is behind its own box, clipped to its rounded corners,
	with its label sharp over it. Rendered at one and two image pixels per
	layout unit.
**/
class Glass {
	static function main() {
		ThemeState.init(DefaultTheme.bundle(), Light);
		var page = ThemeState.get().color(Background);
		var blobs = [
			{x: -20, y: 10, r: 70, c: 0x2563eb}, {x: 90, y: 90, r: 50, c: 0xf59e0b}, {x: 170, y: -30, r: 80, c: 0xdc2626},
			{x: 270, y: 70, r: 60, c: 0x16a34a}, {x: 360, y: 0, r: 50, c: 0x9333ea}, {x: 420, y: 80, r: 70, c: 0x0891b2},
			{x: 530, y: 10, r: 60, c: 0xdb2777}, {x: 600, y: 100, r: 50, c: 0x65a30d}, {x: 0, y: 190, r: 60, c: 0x9333ea},
			{x: 110, y: 240, r: 70, c: 0x16a34a}, {x: 230, y: 180, r: 55, c: 0x2563eb}, {x: 320, y: 260, r: 65, c: 0xf59e0b},
			{x: 430, y: 190, r: 60, c: 0xdc2626}, {x: 520, y: 260, r: 70, c: 0x0891b2}, {x: 610, y: 200, r: 45, c: 0xdb2777},
			{x: -30, y: 380, r: 65, c: 0xdc2626}, {x: 100, y: 340, r: 55, c: 0x0891b2}, {x: 200, y: 400, r: 70, c: 0x9333ea},
			{x: 330, y: 350, r: 50, c: 0x16a34a}, {x: 420, y: 400, r: 65, c: 0xf59e0b}, {x: 540, y: 350, r: 60, c: 0x2563eb},
		];
		var build = () -> hxx('
			<div width={640} height={520}>
				<for {b in blobs}>
					<div class="absolute rounded-full" left={b.x} top={b.y} width={b.r * 2} height={b.r * 2} bg={Brush.solid(b.c)} />
				</for>
				<text class="absolute text-3xl font-bold text-white" left={24} top={70}>Behind the glass, behind the blur</text>
				<text class="absolute text-3xl font-bold text-white" left={24} top={240}>Frosted glass, tinted from clear to dark</text>
				<div class="absolute flex flex-row gap-3" left={16} top={30} width={608} height={110}>
					<for {r in [0, 2, 4, 8, 16, 32]}>
						<div class="flex flex-col justify-end p-2 rounded-2xl border border-white/30" width={92} height={110} bg={Brush.blur(r)}>
							<text class="text-xs font-bold text-white">blur ${r}</text>
						</div>
					</for>
				</div>
				<div class="absolute flex flex-row gap-3" left={16} top={200} width={608} height={110}>
					<for {a in [0.0, 0.15, 0.3, 0.5, 0.8]}>
						<div class="flex flex-col justify-end p-2 rounded-2xl border border-white/40" width={92} height={110}
							bg={Brush.glass(12, 0xffffff, a, true)}>
							<text class="text-xs font-bold">white ${Std.string(a)}</text>
						</div>
					</for>
					<div class="flex flex-col justify-end p-2 rounded-2xl border border-white/20" width={92} height={110}
						bg={Brush.glass(12, 0x000000, 0.8, true)}>
						<text class="text-xs font-bold text-white">black 0.8</text>
					</div>
				</div>
				<text class="absolute text-3xl font-bold text-white" left={24} top={410}>Tailwind: a colour over a backdrop blur</text>
				<div class="absolute flex flex-row gap-3" left={16} top={370} width={608} height={110}>
					<div class="flex flex-col justify-end p-2 rounded-2xl border border-white/30 bg-white/10 backdrop-blur-sm" width={92} height={110}>
						<text class="text-xs font-bold text-white">white/10 sm</text>
					</div>
					<div class="flex flex-col justify-end p-2 rounded-2xl border border-white/40 bg-white/30 backdrop-blur-md" width={92} height={110}>
						<text class="text-xs font-bold">white/30 md</text>
					</div>
					<div class="flex flex-col justify-end p-2 rounded-2xl border border-white/50 bg-white/60 backdrop-blur-lg" width={92} height={110}>
						<text class="text-xs font-bold">white/60 lg</text>
					</div>
					<div class="flex flex-col justify-end p-2 rounded-2xl border border-white/20 bg-black/40 backdrop-blur-xl" width={92} height={110}>
						<text class="text-xs font-bold text-white">black/40 xl</text>
					</div>
					<div class="flex flex-col justify-end p-2 rounded-2xl border border-white/30 bg-primary/30 backdrop-blur-2xl" width={92} height={110}>
						<text class="text-xs font-bold text-white">primary/30 2xl</text>
					</div>
					<div class="flex flex-col justify-end p-2 rounded-2xl border border-white/30 backdrop-blur-3xl" width={92} height={110}>
						<text class="text-xs font-bold text-white">3xl</text>
					</div>
				</div>
			</div>
		');
		Snapshot.scene("glass", 640, 520, build, page.rgb(), page.a);
		Snapshot.scene("glass@2x", 640, 520, build, page.rgb(), page.a, 2.0);
	}
}
