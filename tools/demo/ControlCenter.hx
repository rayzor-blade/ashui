import ashui.components.Button;
import ashui.components.Card;
import ashui.components.Library;
import ashui.components.Slider;
import ashui.components.Toggle;
import ashui.components.Toggle.ToggleGroup;
import ashui.components.Toggle.ToggleGroupItem;
import ashui.core.render.Snapshot;
import ashui.css.Css;
import ashui.css.CompiledCss;
import ashui.layout.Element;
import ashui.reactive.Signal;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
#if ashui_window
import ashui.app.WindowConfig;
import ashui.app.WindowedApp;
#end

/**
	An iOS Control Center study built entirely with HXX elements, including
	SVG icons, the background, and the existing Button, Toggle and Slider.
	Icons are from Tabler, with Lucide's flashlight; see licenses/icons/.
	A regular, opaque window: the home screen is blurred and dimmed first,
	then tinted liquid-glass widgets are layered over it with sharp content.

	    tools/demo/run.sh ControlCenter.hx
	    tools/snapshot/run.sh tools/demo/ControlCenter.hx

	The snapshot run also captures the blurred background alone, so the
	first blur can be inspected independently of the widgets' own blur.
**/
class ControlCenter {
	public static inline var WIDTH = 414;
	public static inline var HEIGHT = 896;
	static var styled = false;

	public static function page():Element
		return build(true);

	static function build(widgets:Bool):Element {
		if (!styled) {
			Library.use();
			Css.add(CompiledCss.file("ControlCenter.css"));
			styled = true;
		}
		var editing = Signal.make(false);
		var playing = Signal.make(false);
		var brightness = Signal.make(52.0);
		var volume = Signal.make(13.0);
		var category = Signal.make(["favorites"]);
		return <div class="cc overflow-hidden" width={WIDTH} height={HEIGHT}>
			<div class="cc-home-screen absolute" left={0} top={0} width={WIDTH} height={HEIGHT}>
				<div class="absolute rounded-2xl items-center justify-center cc-app-0" left={36} top={73} width={59} height={59}>
					<svg width={33} height={33} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
						<path d="M3 17a3 3 0 1 0 6 0a3 3 0 0 0 -6 0" />
						<path d="M13 17a3 3 0 1 0 6 0a3 3 0 0 0 -6 0" />
						<path d="M9 17v-13h10v13" />
						<path d="M9 8h10" />
					</svg>
				</div>
				<div class="absolute rounded-2xl items-center justify-center cc-app-1" left={124} top={73} width={59} height={59}>
					<svg width={33} height={33} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
						<path d="M5 7h1a2 2 0 0 0 2 -2a1 1 0 0 1 1 -1h6a1 1 0 0 1 1 1a2 2 0 0 0 2 2h1a2 2 0 0 1 2 2v9a2 2 0 0 1 -2 2h-14a2 2 0 0 1 -2 -2v-9a2 2 0 0 1 2 -2" />
						<path d="M9 13a3 3 0 1 0 6 0a3 3 0 0 0 -6 0" />
					</svg>
				</div>
				<div class="absolute rounded-2xl items-center justify-center cc-app-2" left={212} top={73} width={59} height={59}>
					<svg width={33} height={33} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
						<path d="M3.06 13a9 9 0 1 0 .49 -4.087" />
						<path d="M3 4.001v5h5" />
						<path d="M11 12a1 1 0 1 0 2 0a1 1 0 1 0 -2 0" />
					</svg>
				</div>
				<div class="absolute rounded-2xl items-center justify-center cc-app-3" left={300} top={73} width={59} height={59}>
					<svg width={33} height={33} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
						<path d="M6 18l0 -3" />
						<path d="M10 18l0 -6" />
						<path d="M14 18l0 -9" />
						<path d="M18 18l0 -12" />
					</svg>
				</div>
				<div class="absolute rounded-2xl items-center justify-center cc-app-4" left={36} top={171} width={59} height={59}>
					<svg width={33} height={33} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
						<path d="M3 19l.01 0" />
						<path d="M7 19a4 4 0 0 0 -4 -4" />
						<path d="M11 19a8 8 0 0 0 -8 -8" />
						<path d="M15 19h3a3 3 0 0 0 3 -3v-8a3 3 0 0 0 -3 -3h-12a3 3 0 0 0 -2.8 2" />
					</svg>
				</div>
				<div class="absolute rounded-2xl items-center justify-center cc-app-5" left={124} top={171} width={59} height={59}>
					<svg width={33} height={33} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
						<path d="M8 12a4 4 0 1 0 8 0a4 4 0 1 0 -8 0" />
						<path d="M3 12h1m8 -9v1m8 8h1m-9 8v1m-6.4 -15.4l.7 .7m12.1 -.7l-.7 .7m0 11.4l.7 .7m-12.1 -.7l-.7 .7" />
					</svg>
				</div>
				<div class="absolute rounded-2xl items-center justify-center cc-app-6" left={212} top={171} width={59} height={59}>
					<svg width={33} height={33} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
						<path d="M3 12a9 9 0 1 0 18 0a9 9 0 0 0 -18 0" />
						<path d="M3.6 9h16.8" />
						<path d="M3.6 15h16.8" />
						<path d="M11.5 3a17 17 0 0 0 0 18" />
						<path d="M12.5 3a17 17 0 0 1 0 18" />
					</svg>
				</div>
				<div class="absolute rounded-2xl items-center justify-center cc-app-7" left={300} top={171} width={59} height={59}>
					<svg width={33} height={33} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
						<path d="M19.5 12.572l-7.5 7.428l-7.5 -7.428a5 5 0 1 1 7.5 -6.566a5 5 0 1 1 7.5 6.572" />
					</svg>
				</div>
				<div class="absolute rounded-2xl items-center justify-center cc-app-8" left={36} top={269} width={59} height={59}>
					<svg width={33} height={33} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
						<path d="M5 12l-2 0l9 -9l9 9l-2 0" />
						<path d="M5 12v7a2 2 0 0 0 2 2h10a2 2 0 0 0 2 -2v-7" />
						<path d="M9 21v-6a2 2 0 0 1 2 -2h2a2 2 0 0 1 2 2v6" />
					</svg>
				</div>
				<div class="absolute rounded-2xl items-center justify-center cc-app-9" left={124} top={269} width={59} height={59}>
					<svg width={33} height={33} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
						<path d="M20 4v8" />
						<path d="M16 4.5v7" />
						<path d="M12 5v16" />
						<path d="M8 5.5v5" />
						<path d="M4 6v4" />
						<path d="M20 8h-16" />
					</svg>
				</div>
				<div class="absolute rounded-2xl items-center justify-center cc-app-10" left={212} top={269} width={59} height={59}>
					<svg width={33} height={33} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
						<path d="M7 4v16l13 -8l-13 -8" />
					</svg>
				</div>
				<div class="absolute rounded-2xl items-center justify-center cc-app-11" left={300} top={269} width={59} height={59}>
					<svg width={33} height={33} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
						<path d="M12 18l.01 0" />
						<path d="M9.172 15.172a4 4 0 0 1 5.656 0" />
						<path d="M6.343 12.343a8 8 0 0 1 11.314 0" />
						<path d="M3.515 9.515c4.686 -4.687 12.284 -4.687 17 0" />
					</svg>
				</div>
				<div class="absolute rounded-2xl items-center justify-center cc-app-12" left={36} top={367} width={59} height={59}>
					<svg width={33} height={33} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
						<path d="M3 17a3 3 0 1 0 6 0a3 3 0 0 0 -6 0" />
						<path d="M13 17a3 3 0 1 0 6 0a3 3 0 0 0 -6 0" />
						<path d="M9 17v-13h10v13" />
						<path d="M9 8h10" />
					</svg>
				</div>
				<div class="absolute rounded-2xl items-center justify-center cc-app-13" left={124} top={367} width={59} height={59}>
					<svg width={33} height={33} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
						<path d="M5 7h1a2 2 0 0 0 2 -2a1 1 0 0 1 1 -1h6a1 1 0 0 1 1 1a2 2 0 0 0 2 2h1a2 2 0 0 1 2 2v9a2 2 0 0 1 -2 2h-14a2 2 0 0 1 -2 -2v-9a2 2 0 0 1 2 -2" />
						<path d="M9 13a3 3 0 1 0 6 0a3 3 0 0 0 -6 0" />
					</svg>
				</div>
				<div class="absolute rounded-2xl items-center justify-center cc-app-14" left={212} top={367} width={59} height={59}>
					<svg width={33} height={33} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
						<path d="M3.06 13a9 9 0 1 0 .49 -4.087" />
						<path d="M3 4.001v5h5" />
						<path d="M11 12a1 1 0 1 0 2 0a1 1 0 1 0 -2 0" />
					</svg>
				</div>
				<div class="absolute rounded-2xl items-center justify-center cc-app-15" left={300} top={367} width={59} height={59}>
					<svg width={33} height={33} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
						<path d="M6 18l0 -3" />
						<path d="M10 18l0 -6" />
						<path d="M14 18l0 -9" />
						<path d="M18 18l0 -12" />
					</svg>
				</div>
				<div class="absolute rounded-2xl items-center justify-center cc-app-12" left={36} top={499} width={59} height={59}>
					<svg width={33} height={33} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
						<path d="M3 17a3 3 0 1 0 6 0a3 3 0 0 0 -6 0" />
						<path d="M13 17a3 3 0 1 0 6 0a3 3 0 0 0 -6 0" />
						<path d="M9 17v-13h10v13" />
						<path d="M9 8h10" />
					</svg>
				</div>
				<div class="absolute rounded-2xl items-center justify-center cc-app-13" left={124} top={499} width={59} height={59}>
					<svg width={33} height={33} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
						<path d="M5 7h1a2 2 0 0 0 2 -2a1 1 0 0 1 1 -1h6a1 1 0 0 1 1 1a2 2 0 0 0 2 2h1a2 2 0 0 1 2 2v9a2 2 0 0 1 -2 2h-14a2 2 0 0 1 -2 -2v-9a2 2 0 0 1 2 -2" />
						<path d="M9 13a3 3 0 1 0 6 0a3 3 0 0 0 -6 0" />
					</svg>
				</div>
				<div class="absolute rounded-2xl items-center justify-center cc-app-14" left={212} top={499} width={59} height={59}>
					<svg width={33} height={33} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
						<path d="M3.06 13a9 9 0 1 0 .49 -4.087" />
						<path d="M3 4.001v5h5" />
						<path d="M11 12a1 1 0 1 0 2 0a1 1 0 1 0 -2 0" />
					</svg>
				</div>
				<div class="absolute rounded-2xl items-center justify-center cc-app-15" left={300} top={499} width={59} height={59}>
					<svg width={33} height={33} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
						<path d="M6 18l0 -3" />
						<path d="M10 18l0 -6" />
						<path d="M14 18l0 -9" />
						<path d="M18 18l0 -12" />
					</svg>
				</div>
				<div class="absolute rounded-2xl items-center justify-center cc-app-16" left={36} top={615} width={59} height={59}>
					<svg width={33} height={33} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
						<path d="M3 19l.01 0" />
						<path d="M7 19a4 4 0 0 0 -4 -4" />
						<path d="M11 19a8 8 0 0 0 -8 -8" />
						<path d="M15 19h3a3 3 0 0 0 3 -3v-8a3 3 0 0 0 -3 -3h-12a3 3 0 0 0 -2.8 2" />
					</svg>
				</div>
				<div class="absolute rounded-2xl items-center justify-center cc-app-17" left={124} top={615} width={59} height={59}>
					<svg width={33} height={33} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
						<path d="M8 12a4 4 0 1 0 8 0a4 4 0 1 0 -8 0" />
						<path d="M3 12h1m8 -9v1m8 8h1m-9 8v1m-6.4 -15.4l.7 .7m12.1 -.7l-.7 .7m0 11.4l.7 .7m-12.1 -.7l-.7 .7" />
					</svg>
				</div>
				<div class="absolute rounded-2xl items-center justify-center cc-app-18" left={212} top={615} width={59} height={59}>
					<svg width={33} height={33} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
						<path d="M3 12a9 9 0 1 0 18 0a9 9 0 0 0 -18 0" />
						<path d="M3.6 9h16.8" />
						<path d="M3.6 15h16.8" />
						<path d="M11.5 3a17 17 0 0 0 0 18" />
						<path d="M12.5 3a17 17 0 0 1 0 18" />
					</svg>
				</div>
				<div class="absolute rounded-2xl items-center justify-center cc-app-19" left={300} top={615} width={59} height={59}>
					<svg width={33} height={33} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
						<path d="M19.5 12.572l-7.5 7.428l-7.5 -7.428a5 5 0 1 1 7.5 -6.566a5 5 0 1 1 7.5 6.572" />
					</svg>
				</div>
				<div class="absolute rounded-3xl bg-white/12" left={18} top={792} width={378} height={89} />
				<div class="absolute rounded-2xl items-center justify-center cc-app-20" left={33} top={807} width={62} height={62}>
					<svg width={35} height={35} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
						<path d="M9 15l6 -6" />
						<path d="M11 6l.463 -.536a5 5 0 0 1 7.071 7.072l-.534 .464" />
						<path d="M13 18l-.397 .534a5.068 5.068 0 0 1 -7.127 0a4.972 4.972 0 0 1 0 -7.071l.524 -.463" />
					</svg>
				</div>
				<div class="absolute rounded-2xl items-center justify-center cc-app-21" left={123} top={807} width={62} height={62}>
					<svg width={35} height={35} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
						<path d="M3 12a9 9 0 1 0 18 0a9 9 0 0 0 -18 0" />
						<path d="M3.6 9h16.8" />
						<path d="M3.6 15h16.8" />
						<path d="M11.5 3a17 17 0 0 0 0 18" />
						<path d="M12.5 3a17 17 0 0 1 0 18" />
					</svg>
				</div>
				<div class="absolute rounded-2xl items-center justify-center cc-app-22" left={213} top={807} width={62} height={62}>
					<svg width={35} height={35} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
						<path d="M3 17a3 3 0 1 0 6 0a3 3 0 0 0 -6 0" />
						<path d="M13 17a3 3 0 1 0 6 0a3 3 0 0 0 -6 0" />
						<path d="M9 17v-13h10v13" />
						<path d="M9 8h10" />
					</svg>
				</div>
				<div class="absolute rounded-2xl items-center justify-center cc-app-23" left={303} top={807} width={62} height={62}>
					<svg width={35} height={35} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
						<path d="M19.5 12.572l-7.5 7.428l-7.5 -7.428a5 5 0 1 1 7.5 -6.566a5 5 0 1 1 7.5 6.572" />
					</svg>
				</div>
			</div>
			<!-- Blur and dim the entire home screen before adding any glass or foreground content. -->
			<div class="absolute bg-black/40 backdrop-blur-md" left={0} top={0} width={WIDTH} height={HEIGHT} />
			<if {widgets}>
				<div class="absolute" left={0} top={0} width={WIDTH} height={HEIGHT}>
					<toggle id="cc-edit" pressed={editing} class="cc-action absolute" left={39} top={22} width={26} height={28}>
						<svg width={18} height={18} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
							<path d="M12 5l0 14" />
							<path d="M5 12l14 0" />
						</svg>
					</toggle>
					<button id="cc-power" variant={Ghost} type="button" onClick={_ -> quit()} class="cc-action absolute" left={350} top={22} width={26} height={28}>
						<svg width={19} height={19} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
							<path d="M7 6a7.75 7.75 0 1 0 10 0" />
							<path d="M12 4l0 8" />
						</svg>
					</button>
					<div class="absolute flex-row items-center gap-1.5 text-white" left={51} top={105}>
						<svg width={22} height={22} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
							<path d="M6 18l0 .01" />
							<path d="M10 18l0 .01" />
							<path d="M14 18l0 .01" />
							<path d="M18 18l0 .01" />
						</svg>
						<text fontSize={16}>No Service</text>
							<svg width={19} height={19} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
								<path d="M12 18l.01 0" />
								<path d="M9.172 15.172a4 4 0 0 1 5.656 0" />
								<path d="M6.343 12.343a8 8 0 0 1 11.314 0" />
								<path d="M3.515 9.515c4.686 -4.687 12.284 -4.687 17 0" />
							</svg>
					</div>
					<div class="absolute flex-row items-center gap-1 text-white" left={271} top={105}>
						<svg width={15} height={15} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
							<path d="M4.05 11a8 8 0 1 1 .5 4m-.5 5v-5h5" />
							<g transform="translate(6.6 6.6) scale(0.45)" fill="none" stroke="currentColor" stroke-width="2">
								<path d="M5 13a2 2 0 0 1 2 -2h10a2 2 0 0 1 2 2v6a2 2 0 0 1 -2 2h-10a2 2 0 0 1 -2 -2v-6" />
								<path d="M11 16a1 1 0 1 0 2 0a1 1 0 0 0 -2 0" />
								<path d="M8 11v-4a4 4 0 1 1 8 0v4" />
							</g>
						</svg>
						<text fontSize={16}>0%</text>
							<svg width={33} height={33} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
								<path d="M6 7h11a2 2 0 0 1 2 2v.5a.5 .5 0 0 0 .5 .5a.5 .5 0 0 1 .5 .5v3a.5 .5 0 0 1 -.5 .5a.5 .5 0 0 0 -.5 .5v.5a2 2 0 0 1 -2 2h-11a2 2 0 0 1 -2 -2v-6a2 2 0 0 1 2 -2" />
							</svg>
					</div>

					<card class="cc-panel absolute bg-glass hover:glass-aberration-100 glass-blur-3 glass-aberration-12 glass-bevel-35 glass-inset" left={45} top={156} width={154} height={154} outlineWidth={editing.get() ? 1 : 0}>
						<toggle id="cc-airplane" pressed={false} class="cc-control absolute rounded-full bg-glass hover:glass-aberration-100 glass-blur-2 glass-aberration-10 glass-bevel-35 glass-inset" left={13} top={13} width={57} height={57}>
							<svg width={26} height={26} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
								<path d="M16 10h4a2 2 0 0 1 0 4h-4l-4 7h-3l2 -7h-4l-2 2h-3l2 -4l-2 -4h3l2 2h4l-2 -7h3l4 7" />
							</svg>
						</toggle>
						<toggle id="cc-airdrop" pressed={true} class="cc-control absolute rounded-full bg-glass hover:glass-aberration-100 glass-blur-2 glass-aberration-10 glass-bevel-35 glass-inset" left={83} top={13} width={57} height={57}>
							<svg width={27} height={27} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
								<path d="M12 12l0 .01" />
								<path d="M14.828 9.172a4 4 0 0 1 0 5.656" />
								<path d="M17.657 6.343a8 8 0 0 1 0 11.314" />
								<path d="M9.168 14.828a4 4 0 0 1 0 -5.656" />
								<path d="M6.337 17.657a8 8 0 0 1 0 -11.314" />
							</svg>
						</toggle>
						<toggle id="cc-wifi" pressed={true} class="cc-control absolute rounded-full bg-glass hover:glass-aberration-100 glass-blur-2 glass-aberration-10 glass-bevel-35 glass-inset" left={13} top={83} width={57} height={57}>
							<svg width={30} height={30} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
								<path d="M12 18l.01 0" />
								<path d="M9.172 15.172a4 4 0 0 1 5.656 0" />
								<path d="M6.343 12.343a8 8 0 0 1 11.314 0" />
								<path d="M3.515 9.515c4.686 -4.687 12.284 -4.687 17 0" />
							</svg>
						</toggle>
						<toggle id="cc-signal" pressed={false} class="cc-control absolute rounded-full bg-white/16 backdrop-blur-sm" left={83} top={83} width={26} height={26}>
							<svg width={17} height={17} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
								<path d="M6 18l0 -3" />
								<path d="M10 18l0 -6" />
								<path d="M14 18l0 -9" />
								<path d="M18 18l0 -12" />
							</svg>
						</toggle>
						<toggle id="cc-bluetooth" pressed={true} class="cc-control absolute rounded-full bg-glass hover:glass-aberration-100 glass-blur-2 glass-aberration-10 glass-bevel-35 glass-inset" left={115} top={83} width={26} height={26}>
							<svg width={18} height={18} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
								<path d="M7 8l10 8l-5 4l0 -16l5 4l-10 8" />
							</svg>
						</toggle>
						<toggle id="cc-link" pressed={true} class="cc-control cc-green absolute rounded-full bg-glass hover:glass-aberration-100 glass-blur-2 glass-aberration-10 glass-bevel-35 glass-inset" left={83} top={115} width={26} height={26}>
							<svg width={18} height={18} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
								<path d="M9 15l6 -6" />
								<path d="M11 6l.463 -.536a5 5 0 0 1 7.071 7.072l-.534 .464" />
								<path d="M13 18l-.397 .534a5.068 5.068 0 0 1 -7.127 0a4.972 4.972 0 0 1 0 -7.071l.524 -.463" />
							</svg>
						</toggle>
						<toggle id="cc-globe" pressed={true} class="cc-control cc-green absolute rounded-full bg-glass hover:glass-aberration-100 glass-blur-2 glass-aberration-10 glass-bevel-35 glass-inset" left={115} top={115} width={26} height={26}>
							<svg width={18} height={18} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
								<path d="M3 12a9 9 0 1 0 18 0a9 9 0 0 0 -18 0" />
								<path d="M3.6 9h16.8" />
								<path d="M3.6 15h16.8" />
								<path d="M11.5 3a17 17 0 0 0 0 18" />
								<path d="M12.5 3a17 17 0 0 1 0 18" />
							</svg>
						</toggle>
					</card>

					<card class="cc-panel absolute bg-glass hover:glass-aberration-100 glass-blur-3 glass-aberration-12 glass-bevel-35 glass-inset" left={215} top={156} width={154} height={154} outlineWidth={editing.get() ? 1 : 0}>
						<div class="absolute rounded-2xl bg-white/8" left={13} top={13} width={53} height={53} />
						<toggle id="cc-airplay" class="cc-control absolute rounded-full bg-glass hover:glass-aberration-100 glass-blur-2 glass-aberration-10 glass-bevel-35 glass-inset" left={100} top={13} width={41} height={41}>
							<svg width={23} height={23} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
								<path d="M3 19l.01 0" />
								<path d="M7 19a4 4 0 0 0 -4 -4" />
								<path d="M11 19a8 8 0 0 0 -8 -8" />
								<path d="M15 19h3a3 3 0 0 0 3 -3v-8a3 3 0 0 0 -3 -3h-12a3 3 0 0 0 -2.8 2" />
							</svg>
						</toggle>
						<text class="absolute" left={15} top={84} fontSize={14} wrap={false}>${playing.get() ? "Glass Animals" : "Not Playing"}</text>
						<button id="cc-back" variant={Ghost} type="button" onClick={_ -> playing.set(false)} class="cc-action absolute" left={15} top={116} width={34} height={28}>
							<svg width={26} height={26} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
								<path d="M21 5v14l-8 -7l8 -7" />
								<path d="M10 5v14l-8 -7l8 -7" />
							</svg>
						</button>
						<toggle id="cc-play" pressed={playing} class="cc-action cc-play absolute" left={62} top={114} width={32} height={30}>
							<svg class="cc-play-icon" width={27} height={27} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
								<path d="M7 4v16l13 -8l-13 -8" />
							</svg>
							<svg class="cc-pause-icon" width={27} height={27} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
								<path d="M6 6a1 1 0 0 1 1 -1h2a1 1 0 0 1 1 1v12a1 1 0 0 1 -1 1h-2a1 1 0 0 1 -1 -1l0 -12" />
								<path d="M14 6a1 1 0 0 1 1 -1h2a1 1 0 0 1 1 1v12a1 1 0 0 1 -1 1h-2a1 1 0 0 1 -1 -1l0 -12" />
							</svg>
						</toggle>
						<button id="cc-next" variant={Ghost} type="button" onClick={_ -> playing.set(true)} class="cc-action absolute" left={109} top={116} width={30} height={28}>
							<svg width={26} height={26} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
								<path d="M3 5v14l8 -7l-8 -7" />
								<path d="M14 5v14l8 -7l-8 -7" />
							</svg>
						</button>
					</card>

					<toggle id="cc-lock" pressed={true} class="cc-control cc-lock absolute rounded-full bg-glass hover:glass-aberration-100 glass-blur-2 glass-aberration-10 glass-bevel-35 glass-inset" left={45} top={326} width={70} height={70}>
						<svg width={38} height={38} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
							<path d="M4.05 11a8 8 0 1 1 .5 4m-.5 5v-5h5" />
							<g transform="translate(6.6 6.6) scale(0.45)" fill="none" stroke="currentColor" stroke-width="2">
								<path d="M5 13a2 2 0 0 1 2 -2h10a2 2 0 0 1 2 2v6a2 2 0 0 1 -2 2h-10a2 2 0 0 1 -2 -2v-6" />
								<path d="M11 16a1 1 0 1 0 2 0a1 1 0 0 0 -2 0" />
								<path d="M8 11v-4a4 4 0 1 1 8 0v4" />
							</g>
						</svg>
					</toggle>

					<toggle id="cc-mirror" pressed={false} class="cc-control cc-tool absolute rounded-full bg-glass hover:glass-aberration-100 glass-blur-2 glass-aberration-10 glass-bevel-35 glass-inset" left={130} top={326} width={70} height={70}>
						<svg width={36} height={36} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
							<path d="M11 19h-6a2 2 0 0 1 -2 -2v-10a2 2 0 0 1 2 -2h14a2 2 0 0 1 2 2v4" />
							<path d="M14 15a1 1 0 0 1 1 -1h5a1 1 0 0 1 1 1v3a1 1 0 0 1 -1 1h-5a1 1 0 0 1 -1 -1l0 -3" />
						</svg>
					</toggle>

					<slider id="cc-brightness" value={brightness} min={0} max={100} step={1} orientation="vertical"
						class="cc-level cc-brightness absolute rounded-full bg-glass hover:glass-aberration-100 glass-blur-3 glass-aberration-12 glass-bevel-35 glass-inset" left={215} top={326} width={70} height={154}>
						<div class="absolute" left={19.5} bottom={19} width={31} height={31}>
							<svg width={31} height={31} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
								<path d="M8 12a4 4 0 1 0 8 0a4 4 0 1 0 -8 0" />
								<path d="M3 12h1m8 -9v1m8 8h1m-9 8v1m-6.4 -15.4l.7 .7m12.1 -.7l-.7 .7m0 11.4l.7 .7m-12.1 -.7l-.7 .7" />
							</svg>
						</div>
					</slider>

					<slider id="cc-volume" value={volume} min={0} max={100} step={1} orientation="vertical"
						class="cc-level cc-volume absolute rounded-full bg-glass hover:glass-aberration-100 glass-blur-3 glass-aberration-12 glass-bevel-35 glass-inset" left={300} top={326} width={70} height={154}>
						<div class="absolute text-white" left={20.5} bottom={19} width={29} height={29}>
							<svg width={29} height={29} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
								<path d="M15 8a5 5 0 0 1 0 8" />
								<path d="M17.7 5a9 9 0 0 1 0 14" />
								<path d="M6 15h-2a1 1 0 0 1 -1 -1v-4a1 1 0 0 1 1 -1h2l3.5 -4.5a.8 .8 0 0 1 1.5 .5v14a.8 .8 0 0 1 -1.5 .5l-3.5 -4.5" />
							</svg>
						</div>
					</slider>

					<toggle id="cc-focus" class="cc-control cc-focus absolute rounded-full bg-glass hover:glass-aberration-100 glass-blur-2 glass-aberration-10 glass-bevel-35 glass-inset" left={45} top={411} width={154} height={69}>
						<div class="absolute rounded-full bg-white/15 items-center justify-center" left={14} top={14} width={42} height={42}>
							<svg width={28} height={28} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
								<path d="M12 3c.132 0 .263 0 .393 0a7.5 7.5 0 0 0 7.92 12.446a9 9 0 1 1 -8.313 -12.454l0 .008" />
							</svg>
						</div>
						<text class="absolute" left={64} top={26} fontSize={14}>Focus</text>
						<div class="absolute" left={108} top={28} width={12} height={12}>
							<svg width={12} height={12} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
								<path d="M8 9l4 -4l4 4" />
								<path d="M16 15l-4 4l-4 -4" />
							</svg>
						</div>
					</toggle>

					<card class="cc-panel cc-home absolute bg-glass hover:glass-aberration-100 glass-blur-3 glass-aberration-12 glass-bevel-35 glass-inset" left={45} top={496} width={154} height={154} outlineWidth={editing.get() ? 1 : 0}>
						<div class="absolute" left={53} top={44} width={48} height={48}>
							<svg width={48} height={48} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
								<path d="M5 12l-2 0l9 -9l9 9l-2 0" />
								<path d="M5 12v7a2 2 0 0 0 2 2h10a2 2 0 0 0 2 -2v-7" />
								<path d="M9 21v-6a2 2 0 0 1 2 -2h2a2 2 0 0 1 2 2v6" />
							</svg>
						</div>
						<text class="absolute" left={27} top={98} fontSize={13} wrap={false}>No Home Set Up</text>
					</card>

					<toggle id="cc-flashlight" class="cc-control cc-tool absolute rounded-full bg-glass hover:glass-aberration-100 glass-blur-2 glass-aberration-10 glass-bevel-35 glass-inset" left={215} top={496} width={70} height={70} outlineWidth={editing.get() ? 1 : 0}>
						<svg width={37} height={37} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
							<path d="M12 13v1" />
							<path d="M17 2a1 1 0 0 1 1 1v4a3 3 0 0 1-.6 1.8l-.6.8A4 4 0 0 0 16 12v8a2 2 0 0 1-2 2H10a2 2 0 0 1-2-2v-8a4 4 0 0 0-.8-2.4l-.6-.8A3 3 0 0 1 6 7V3a1 1 0 0 1 1-1z" />
							<path d="M6 6h12" />
						</svg>
					</toggle>

					<toggle id="cc-timer" class="cc-control cc-tool absolute rounded-full bg-glass hover:glass-aberration-100 glass-blur-2 glass-aberration-10 glass-bevel-35 glass-inset" left={300} top={496} width={70} height={70} outlineWidth={editing.get() ? 1 : 0}>
						<svg width={38} height={38} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
							<path d="M3.06 13a9 9 0 1 0 .49 -4.087" />
							<path d="M3 4.001v5h5" />
							<path d="M11 12a1 1 0 1 0 2 0a1 1 0 1 0 -2 0" />
						</svg>
					</toggle>

					<toggle id="cc-calculator" class="cc-control cc-tool absolute rounded-full bg-glass hover:glass-aberration-100 glass-blur-2 glass-aberration-10 glass-bevel-35 glass-inset" left={215} top={581} width={70} height={70} outlineWidth={editing.get() ? 1 : 0}>
						<svg width={37} height={37} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
							<path d="M4 5a2 2 0 0 1 2 -2h12a2 2 0 0 1 2 2v14a2 2 0 0 1 -2 2h-12a2 2 0 0 1 -2 -2l0 -14" />
							<path d="M8 8a1 1 0 0 1 1 -1h6a1 1 0 0 1 1 1v1a1 1 0 0 1 -1 1h-6a1 1 0 0 1 -1 -1l0 -1" />
							<path d="M8 14l0 .01" />
							<path d="M12 14l0 .01" />
							<path d="M16 14l0 .01" />
							<path d="M8 17l0 .01" />
							<path d="M12 17l0 .01" />
							<path d="M16 17l0 .01" />
						</svg>
					</toggle>

					<toggle id="cc-camera" class="cc-control cc-tool absolute rounded-full bg-glass hover:glass-aberration-100 glass-blur-2 glass-aberration-10 glass-bevel-35 glass-inset" left={300} top={581} width={70} height={70} outlineWidth={editing.get() ? 1 : 0}>
						<svg width={38} height={38} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
							<path d="M5 7h1a2 2 0 0 0 2 -2a1 1 0 0 1 1 -1h6a1 1 0 0 1 1 1a2 2 0 0 0 2 2h1a2 2 0 0 1 2 2v9a2 2 0 0 1 -2 2h-14a2 2 0 0 1 -2 -2v-9a2 2 0 0 1 2 -2" />
							<path d="M9 13a3 3 0 1 0 6 0a3 3 0 0 0 -6 0" />
						</svg>
					</toggle>

					<toggle id="cc-record" class="cc-control cc-tool absolute rounded-full bg-glass hover:glass-aberration-100 glass-blur-2 glass-aberration-10 glass-bevel-35 glass-inset" left={45} top={666} width={70} height={70} outlineWidth={editing.get() ? 1 : 0}>
						<svg width={39} height={39} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
							<path d="M11 12a1 1 0 1 0 2 0a1 1 0 1 0 -2 0" />
							<path d="M3 12a9 9 0 1 0 18 0a9 9 0 1 0 -18 0" />
						</svg>
					</toggle>

					<toggle id="cc-shazam" class="cc-control cc-tool absolute rounded-full bg-glass hover:glass-aberration-100 glass-blur-2 glass-aberration-10 glass-bevel-35 glass-inset" left={130} top={666} width={70} height={70} outlineWidth={editing.get() ? 1 : 0}>
						<svg width={38} height={38} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
							<path d="M10 12l2 -2a2.828 2.828 0 0 1 4 0a2.828 2.828 0 0 1 0 4l-3 3" />
							<path d="M14 12l-2 2a2.828 2.828 0 1 1 -4 -4l3 -3" />
							<path d="M3 12a9 9 0 1 0 18 0a9 9 0 1 0 -18 0" />
						</svg>
					</toggle>

					<toggle id="cc-currency" class="cc-control cc-tool absolute rounded-full bg-glass hover:glass-aberration-100 glass-blur-2 glass-aberration-10 glass-bevel-35 glass-inset opacity-50" left={215} top={666} width={70} height={70} outlineWidth={editing.get() ? 1 : 0}>
						<svg width={38} height={38} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
							<path d="M16.7 8a3 3 0 0 0 -2.7 -2h-4a3 3 0 0 0 0 6h4a3 3 0 0 1 0 6h-4a3 3 0 0 1 -2.7 -2" />
							<path d="M12 3v3m0 12v3" />
						</svg>
					</toggle>

					<toggle-group value={category} class="cc-rail-group absolute" left={380} top={354} width={23}>
						<toggle-group-item value="favorites" class="cc-rail" width={23} height={26}>
							<svg width={19} height={19} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
								<path d="M19.5 12.572l-7.5 7.428l-7.5 -7.428a5 5 0 1 1 7.5 -6.566a5 5 0 1 1 7.5 6.572" />
							</svg>
						</toggle-group-item>
						<toggle-group-item value="music" class="cc-rail" width={23} height={26}>
							<svg width={19} height={19} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
								<path d="M3 17a3 3 0 1 0 6 0a3 3 0 0 0 -6 0" />
								<path d="M13 17a3 3 0 1 0 6 0a3 3 0 0 0 -6 0" />
								<path d="M9 17v-13h10v13" />
								<path d="M9 8h10" />
							</svg>
						</toggle-group-item>
						<toggle-group-item value="home" class="cc-rail" width={23} height={26}>
							<svg width={19} height={19} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
								<path d="M5 12l-2 0l9 -9l9 9l-2 0" />
								<path d="M5 12v7a2 2 0 0 0 2 2h10a2 2 0 0 0 2 -2v-7" />
								<path d="M9 21v-6a2 2 0 0 1 2 -2h2a2 2 0 0 1 2 2v6" />
							</svg>
						</toggle-group-item>
						<toggle-group-item value="connectivity" class="cc-rail" width={23} height={26}>
							<svg width={19} height={19} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
								<path d="M20 4v8" />
								<path d="M16 4.5v7" />
								<path d="M12 5v16" />
								<path d="M8 5.5v5" />
								<path d="M4 6v4" />
								<path d="M20 8h-16" />
							</svg>
						</toggle-group-item>
					</toggle-group>
				</div>
			</if>
		</div>;
	}

	static function quit() {
		#if ashui_window
		if (WindowedApp.current != null) WindowedApp.current.quit();
		#end
	}

	static function main() {
		ThemeState.init(DefaultTheme.bundle(), Dark);
		#if ashui_window
		WindowedApp.run(new WindowConfig().title("Control Center · Liquid Glass")
			.size(WIDTH, HEIGHT).resizable(false).transparent(false).decorations(true).theme(DefaultTheme.bundle()), page);
		#else
		Snapshot.scene("control-center-backdrop", WIDTH, HEIGHT, () -> build(false), 0x0a2028);
		Snapshot.scene("control-center", WIDTH, HEIGHT, page, 0x0a2028);
		Snapshot.scene("control-center@2x", WIDTH, HEIGHT, page, 0x0a2028, 1.0, 2.0);
		// Rest, hover a card and a circular glass control, then leave.
		Snapshot.sequence("control-center-hover", WIDTH, HEIGHT, page, 30, 4,
			(frame, tree, _) -> switch frame {
				case 1: ashui.input.Pointer.move(tree, 300, 250);
				case 2: ashui.input.Pointer.move(tree, 250, 531);
				case 3: ashui.input.Pointer.leave(tree);
				case _:
			}, 0x0a2028, 1.0, 2.0);
		for (problem in Css.problems)
			Sys.println(problem);
		#end
	}
}
