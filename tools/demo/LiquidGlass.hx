import ashui.app.WindowConfig;
import ashui.app.WindowedApp;
import ashui.input.Interaction;
import ashui.layout.Element;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Brush;
import ashui.types.Style;
import ashui.ui.Hxx.hxx;

/**
	Liquid glass over the desktop: a window with no frame and nothing of its
	own behind the UI, whose one panel is liquid glass. The system blurs
	the desktop behind the panel a little, and draws no shadow, which on a
	transparent window outlines what it draws; the panel's tint and rim
	light are drawn over it. Drag the panel to move the window; the cross or Escape closes
	it.

	    tools/demo/run.sh LiquidGlass.hx
**/
class LiquidGlass {
	static final CLOSE = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M18 6 6 18"/><path d="m6 6 12 12"/></svg>';

	public static function config():WindowConfig
		return new WindowConfig().title("Liquid glass").size(440, 200).transparent(true).decorations(false).shadow(false).blurRadius(6).theme(DefaultTheme.bundle());

	public static function page():Element
		return card(Brush.glass(14, 0xffffff, 0.04, false));

	/** The card, its panel painted with `glass`. **/
	public static function card(glass:Brush):Element {
		var close:Element = hxx('
			<div class="flex items-center justify-center rounded-full text-white/80" width={24} height={24} bg={Brush.solid(0xffffff, 0.12)}>
				{new ashui.ui.Svg(ashui.svg.SvgDocument.parse(CLOSE), {width: 14, height: 14})}
			</div>
		');
		var panel:Element = hxx('
			<div class="flex flex-col gap-3 p-6 rounded-3xl" width={400} height={160} bg={glass}>
				<div class="flex flex-row items-center justify-between">
					<text class="text-xs font-semibold text-white/70 tracking-wide">NOW PLAYING</text>
					{close}
				</div>
				<text class="text-2xl font-bold text-white">Glass Animals</text>
				<text class="text-sm text-white/80">Heat Waves · Dreamland</text>
				<div class="rounded-full" width={352} height={4} bg={Brush.solid(0xffffff, 0.2)}>
					<div class="rounded-full" width={140} height={4} bg={Brush.solid(0xffffff, 0.9)} />
				</div>
			</div>
		');
		var root:Element = hxx('<div width={440} height={200} padding={20}>{panel}</div>');
		// The window has no title bar: a press on the panel moves it.
		Interaction.of(panel.node).onPointerDown(e -> if (e.target == panel.node) WindowedApp.current.window.dragWindow());
		Interaction.of(close.node).onClick(_ -> WindowedApp.current.quit());
		Interaction.of(root.node).setFocusable(true).onKeyDown(e -> switch e.key {
			case Named(Escape): WindowedApp.current.quit();
			case _:
		});
		return root;
	}

	static function main() {
		WindowedApp.run(config(), page);
	}
}
