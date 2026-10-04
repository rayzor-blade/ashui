import ashui.app.WindowConfig;
import ashui.app.WindowedApp;
import ashui.layout.Element;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Brush;
import ashui.types.Style;
import ashui.ui.Div;
import ashui.ui.Ref;
import ashui.ui.Hxx.hxx;

/**
	Liquid glass over the desktop: a window with no frame and nothing of its
	own behind the UI, whose one panel is liquid glass. The system blurs
	the desktop behind the panel only slightly, and draws no shadow, which on a
	transparent window outlines what it draws; the panel's tint and rim
	light are drawn over it. Drag the panel to move the window; the cross or Escape closes
	it.

	    tools/demo/run.sh LiquidGlass.hx
**/
class LiquidGlass {
	static final CLOSE = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M18 6 6 18"/><path d="m6 6 12 12"/></svg>';

	public static function config():WindowConfig
		return new WindowConfig().title("Liquid glass").size(440, 200).transparent(true).decorations(false).shadow(false).blurRadius(2).theme(DefaultTheme.bundle());

	public static function page():Element
		return card(Brush.glass(14, 0x000000, 0.1, false));

	/** The card, its panel painted with `glass`. **/
	public static function card(glass:Brush):Element {
		var panel = new Ref<Div>();
		var close = ashui.svg.SvgDocument.parse(CLOSE);
		// The window has no title bar: a press on the panel itself moves it; the cross and Escape close it.
		var root:Div = hxx('
			<div width={440} height={200} padding={20} focusable={true} onKeyDown={e -> if (e.key.match(Named(Escape))) WindowedApp.current.quit()}>
				<div ref={panel} class="flex flex-col gap-3 p-6 rounded-3xl" width={400} height={160} bg={glass}
					onPointerDown={e -> if (e.target == panel.get().node) WindowedApp.current.window.dragWindow()}>
					<div class="flex flex-row items-center justify-between">
						<text class="text-xs font-semibold text-white/70 tracking-wide">NOW PLAYING</text>
						<div class="flex items-center justify-center rounded-full text-white/80" width={24} height={24} bg={Brush.solid(0xffffff, 0.12)}
							onClick={() -> WindowedApp.current.quit()}>
							{new ashui.ui.Svg(close, {width: 14, height: 14})}
						</div>
					</div>
					<text class="text-2xl font-bold text-white">Glass Animals</text>
					<text class="text-sm text-white/80">Heat Waves · Dreamland</text>
					<div class="rounded-full" width={352} height={4} bg={Brush.solid(0xffffff, 0.2)}>
						<div class="rounded-full" width={140} height={4} bg={Brush.solid(0xffffff, 0.9)} />
					</div>
				</div>
			</div>
		');
		return root;
	}

	static function main() {
		WindowedApp.run(config(), page);
	}
}
