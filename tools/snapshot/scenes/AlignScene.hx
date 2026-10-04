import ashui.components.Avatar;
import ashui.components.Badge;
import ashui.components.Button;
import ashui.components.Kbd;
import ashui.components.Toggle;
import ashui.debug.AlignProbe;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Style;
import ashui.ui.Hxx.hxx;

/**
	How centred text and icons sit in buttons and boxes, measured from what
	is drawn: each box with an id is reported, how far its ink is off its
	middle across and down. Writes `.ashui/snapshots/align/align/`
	(`align-light` with `SCHEME=light`).
**/
class AlignScene {
	static function main() {
		var light = Sys.getEnv("SCHEME") == "light";
		ThemeState.init(DefaultTheme.bundle(), light ? Light : Dark);
		var page = ThemeState.get().color(Background);
		var build = () -> hxx('
			<div flexDirection={Column} padding={24} gap={20} width={760} height={420}>
				<div flexDirection={Row} gap={12} alignItems={Center}>
					<button id="text-sm" size={Sm}>Button</button>
					<button id="text-md">Button</button>
					<button id="text-lg" size={Lg}>Button</button>
					<button id="outline" variant={Outline}>Outline</button>
					<button id="ghost" variant={Ghost}>Ghost</button>
					<button id="lower" variant={Outline}>running</button>
				</div>
				<div flexDirection={Row} gap={12} alignItems={Center}>
					<button id="icon" variant={Outline} size={Icon}><svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12h14"/><path d="M12 5v14"/></svg></button>
					<button id="icon-chevron" variant={Outline} size={Icon}><svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m9 18 6-6-6-6"/></svg></button>
					<button id="icon-text"><svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="20" height="16" x="2" y="4" rx="2"/><path d="m22 7-8.97 5.7a1.94 1.94 0 0 1-2.06 0L2 7"/></svg>Login with Email</button>
					<button id="text-icon" variant={Outline}>Next<svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m9 18 6-6-6-6"/></svg></button>
					<button id="minus" variant={Outline} size={Icon}>-</button>
					<button id="plus" variant={Outline} size={Icon}>+</button>
				</div>
				<div flexDirection={Row} gap={12} alignItems={Center}>
					<badge id="badge">Badge</badge>
					<badge id="badge-secondary" variant={BadgeVariant.Secondary}>Secondary</badge>
					<toggle id="toggle-b">B</toggle>
					<avatar id="avatar"><avatar-fallback>AL</avatar-fallback></avatar>
					<kbd id="kbd">K</kbd>
				</div>
				<div flexDirection={Row} gap={12} alignItems={Center}>
					<div id="box-text" width={140} height={44} alignItems={Center} justifyContent={Justify.Center} class="bg-surface rounded-md"><p>Centered</p></div>
					<div id="box-icon" width={44} height={44} alignItems={Center} justifyContent={Justify.Center} class="bg-surface rounded-md"><svg class="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/></svg></div>
					<div id="box-row" width={160} height={44} flexDirection={Row} gap={8} alignItems={Center} justifyContent={Justify.Center} class="bg-surface rounded-md"><svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/></svg><p>Icon and text</p></div>
					<p id="line-14" class="bg-surface">HHH</p>
					<p id="line-bold" class="bg-surface font-semibold">HHH</p>
					<div id="box-digit" width={44} height={44} alignItems={Center} justifyContent={Justify.Center} class="bg-surface rounded-md"><p>8</p></div>
				</div>
			</div>
		');
		var results = AlignProbe.record(light ? "align-light" : "align", 760, 420, build, 2, page.rgb());
		Sys.println(AlignProbe.report(results));
	}
}
