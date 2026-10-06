import ashui.app.WindowConfig;
import ashui.app.WindowedApp;
import ashui.layout.Element;
import ashui.theme.themes.DefaultTheme;
import ashui.ui.Div;
import ashui.ui.Ref;

/**
	Liquid glass over the desktop: a window with no frame and nothing of its
	own behind the UI, whose one panel is liquid glass. The system blurs
	the desktop behind the panel only slightly, and draws no shadow, which on a
	transparent window outlines what it draws; the panel's tint and rim
	light are drawn over it. Since the desktop is outside the render target,
	the bevel refracts a procedural light field while staying translucent.
	`glass-aberration-100` separates that field's colours at the rim;
	set it to 0 to compare without it.
	Drag the panel to move the window; the cross or Escape closes it.

		tools/demo/run.sh LiquidGlass.hx
**/
class LiquidGlass {
	public static function config():WindowConfig
		return new WindowConfig().title("Liquid glass")
			.size(440, 200)
			.transparent(true)
			.decorations(false)
			.shadow(false)
			.blurRadius(2)
			.theme(DefaultTheme.bundle());

	public static function page():Element
		return card();

	/** The card, painted by the glass utility classes. **/
	public static function card():Element {
		var panel = new Ref<Div>();
		// The window has no title bar: a press on the panel itself moves it; the cross and Escape close it.
		var root:Div = <div width={440} height={200} padding={20} focusable={true} onKeyDown={e -> if (e.key.match(Named(Escape))) WindowedApp.current.quit()}>
			<div ref={panel} class="flex flex-col gap-3 p-6 rounded-3xl bg-glass glass-blur-14 glass-tint-black/10 glass-aberration-100" width={400} height={160}
				onPointerDown={e -> if (e.target == panel.get().node) WindowedApp.current.dragWith(e)}>
				<div class="flex flex-row items-center justify-between">
					<text class="text-xs font-semibold text-white/70 tracking-wide">NOW PLAYING</text>
					<div class="flex items-center justify-center rounded-full text-white/80 bg-white/12" width={24} height={24}
						onClick={() -> WindowedApp.current.quit()}>
						<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" width={14} height={14}>
							<path d="M18 6 6 18" /><path d="m6 6 12 12" />
						</svg>
					</div>
				</div>
				<text class="text-2xl font-bold text-white">Glass Animals</text>
				<text class="text-sm text-white/80">Heat Waves · Dreamland</text>
				<div class="rounded-full bg-white/20" width={352} height={4}>
					<div class="rounded-full bg-white/90" width={140} height={4} />
				</div>
			</div>
		</div>;
		return root;
	}

	static function main() {
		WindowedApp.run(config(), page);
	}
}
