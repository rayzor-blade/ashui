package ashui.theme;

import ashui.animation.AnimatedValue;
import ashui.animation.AnimationScheduler;
import ashui.animation.SpringConfig;
import ashui.reactive.Signal;

/**
	The theme in use, one per program: its bundle and scheme, the tokens
	they give, and overrides of single tokens. Install one with `init` or
	`initDefault`, then reach it with `get`.

	`revision` is a signal bumped on every change. A computed that reads it,
	as each of `Themed`'s does, runs again when the theme changes, so a
	property bound to a token updates and nothing else is rebuilt. The
	redraw callback is called on every change too, so a window draws the
	new look. A scheme switch with a scheduler set animates the colours on
	a gentle spring, advanced by `tick` each frame; every other token
	family switches at once. Mirrors Blinc's `ThemeState`.
**/
class ThemeState {
	static var instance:Null<ThemeState>;
	static var redrawCallback:Null<Void->Void>;
	static final pendingStylesheets:Array<String> = [];

	/** Bumped on every token change; read it in a computed to follow the theme. **/
	public final revision:Signal<Int>;

	var bundle:ThemeBundle;
	var currentScheme:ColorScheme;
	var currentColors:ColorTokens;
	var currentShadows:ShadowTokens;
	var currentSpacing:SpacingTokens;
	var currentTypography:TypographyTokens;
	var currentRadii:RadiusTokens;
	var currentShape:ShapeTokens;
	var currentAnimations:AnimationTokens;

	final colorOverrides = new Map<String, Rgba>();
	final spacingOverrides = new Map<String, Float>();
	final radiusOverrides = new Map<String, Float>();

	var repaint = false;
	var relayout = false;
	var scheduler:Null<AnimationScheduler> = null;

	var progress:Null<AnimatedValue> = null;
	var fromColors:Null<ColorTokens> = null;
	var toColors:Null<ColorTokens> = null;

	#if target.threaded
	final lock = new sys.thread.Mutex();
	#end

	function new(bundle:ThemeBundle, scheme:ColorScheme) {
		revision = Signal.make(0);
		this.bundle = bundle;
		currentScheme = scheme;
		adopt(bundle.forScheme(scheme), true);
	}

	/** Installs `bundle` in `scheme`. Replacing an installed theme clears every override. **/
	public static function init(bundle:ThemeBundle, scheme:ColorScheme):Void {
		for (css in bundle.cssSources)
			pendingStylesheets.push(css);
		if (instance == null) {
			instance = new ThemeState(bundle, scheme);
			return;
		}
		var state = instance;
		state.locked(() -> {
			state.bundle = bundle;
			state.currentScheme = scheme;
			state.adopt(bundle.forScheme(scheme), true);
			state.colorOverrides.clear();
			state.spacingOverrides.clear();
			state.radiusOverrides.clear();
			state.repaint = true;
			state.relayout = true;
		});
		state.changed();
	}

	/** The default theme, in the system's scheme. **/
	public static function initDefault():Void {
		init(ashui.theme.themes.DefaultTheme.bundle(), Platform.detectSystemColorScheme());
	}

	/** The installed theme; throws when there is none. **/
	public static function get():ThemeState {
		if (instance == null)
			throw "ThemeState not initialized: call ThemeState.init or ThemeState.initDefault first";
		return instance;
	}

	/** The installed theme, or null when there is none. **/
	public static function tryGet():Null<ThemeState> {
		return instance;
	}

	/** Calls `callback` on every theme change, so a window loop draws a frame; replaces the last one. **/
	public static function setRedrawCallback(callback:Void->Void):Void {
		redrawCallback = callback;
	}

	/** Style sheets that came with installed bundles, oldest first, once each. **/
	public static function drainPendingStylesheets():Array<String> {
		return pendingStylesheets.splice(0, pendingStylesheets.length);
	}

	/** Animates scheme switches on `scheduler` from now on; null switches at once. **/
	public function setScheduler(scheduler:Null<AnimationScheduler>):Void {
		this.scheduler = scheduler;
	}

	/** The scheme in use. **/
	public function scheme():ColorScheme {
		return currentScheme;
	}

	/**
		Switches to `scheme`. Colours spring from where they are now, even
		mid-transition, when a scheduler is set; the rest switches at once.
	**/
	public function setScheme(scheme:ColorScheme):Void {
		if (scheme == currentScheme)
			return;
		locked(() -> {
			var oldColors = currentColors;
			currentScheme = scheme;
			var theme = bundle.forScheme(scheme);
			adopt(theme, false);
			if (scheduler != null) {
				fromColors = oldColors;
				toColors = theme.colors;
				// 0 to 100 rather than 0 to 1, clear of the spring's settling epsilon.
				var spring = new AnimatedValue(scheduler, 0, SpringConfig.gentle());
				spring.setTarget(100);
				progress = spring;
				currentColors = oldColors;
			} else {
				currentColors = theme.colors;
			}
			repaint = true;
			relayout = true;
		});
		changed();
	}

	/** Switches to the other scheme, as `setScheme` does. **/
	public function toggleScheme():Void {
		setScheme(currentScheme.toggle());
	}

	/**
		Moves a scheme transition on to where its spring is; call once a
		frame. True while it still runs.
	**/
	public function tick():Bool {
		// 0: no transition; 1: moved on; 2: moved on and finished.
		var step = locked(() -> {
			if (progress == null || fromColors == null || toColors == null) {
				progress = null;
				return 0;
			}
			var raw = progress.get();
			currentColors = ColorTokens.lerp(fromColors, toColors, Math.max(0, Math.min(1, raw / 100)));
			if (Math.abs(raw - 100) < 1) {
				// Ends on the target colours, not the last step toward them.
				currentColors = toColors;
				progress = null;
				fromColors = null;
				toColors = null;
				return 2;
			}
			return 1;
		});
		if (step > 0)
			changed();
		return step == 1;
	}

	/** Whether a scheme's colour transition is running. **/
	public function isAnimating():Bool {
		return progress != null && progress.isAnimating();
	}

	// --- colours ---

	/** `token`'s colour: its override, else the theme's. **/
	public function color(token:ColorToken):Rgba {
		var overridden = colorOverrides.get(cast token);
		var value = overridden != null ? overridden : currentColors.get(token);
		debugColor(token, value);
		return value;
	}

	/** The theme's colours, without overrides. **/
	public function colors():ColorTokens {
		return currentColors;
	}

	/** Gives `token` `color` whatever the theme says, until removed or a theme is installed. **/
	public function setColorOverride(token:ColorToken, color:Rgba):Void {
		colorOverrides.set(cast token, color);
		repaint = true;
		changed();
	}

	/** Gives `token` the theme's colour again. **/
	public function removeColorOverride(token:ColorToken):Void {
		colorOverrides.remove(cast token);
		repaint = true;
		changed();
	}

	// --- spacing ---

	/** `token`'s spacing: its override, else the theme's. **/
	public function spacingValue(token:SpacingToken):Float {
		var overridden = spacingOverrides.get(cast token);
		return overridden != null ? overridden : currentSpacing.get(token);
	}

	/** The theme's spacing, without overrides. **/
	public function spacing():SpacingTokens {
		return currentSpacing;
	}

	/** Gives `token` `value` pixels whatever the theme says, until removed or a theme is installed. **/
	public function setSpacingOverride(token:SpacingToken, value:Float):Void {
		spacingOverrides.set(cast token, F32.round(value));
		relayout = true;
		changed();
	}

	/** Gives `token` the theme's spacing again. **/
	public function removeSpacingOverride(token:SpacingToken):Void {
		spacingOverrides.remove(cast token);
		relayout = true;
		changed();
	}

	// --- the rest ---

	/** The theme's type: fonts, sizes, weights, line heights and letter spacing. **/
	public function typography():TypographyTokens {
		return currentTypography;
	}

	/** `token`'s radius: its override, else the theme's. **/
	public function radius(token:RadiusToken):Float {
		var overridden = radiusOverrides.get(cast token);
		return overridden != null ? overridden : currentRadii.get(token);
	}

	/** The theme's radii, without overrides. **/
	public function radii():RadiusTokens {
		return currentRadii;
	}

	/** Gives `token` `value` pixels whatever the theme says; radii only repaint, as they do not change layout. **/
	public function setRadiusOverride(token:RadiusToken, value:Float):Void {
		radiusOverrides.set(cast token, F32.round(value));
		repaint = true;
		changed();
	}

	/** The theme's corner smoothing. **/
	public function shape():ShapeTokens {
		return currentShape;
	}

	/** One value of the theme's corner smoothing. **/
	public function shapeToken(token:ShapeToken):Float {
		return currentShape.get(token);
	}

	/** The theme's shadow stacks. **/
	public function shadows():ShadowTokens {
		return currentShadows;
	}

	/** The theme's durations and curves. **/
	public function animations():AnimationTokens {
		return currentAnimations;
	}

	/** Whether a change since `clearRepaint` alters how things look. **/
	public function needsRepaint():Bool
		return repaint;

	public function clearRepaint():Void
		repaint = false;

	/** Whether a change since `clearLayout` alters sizes, so layout must run again. **/
	public function needsLayout():Bool
		return relayout;

	public function clearLayout():Void
		relayout = false;

	/** Drops every override, so each token is the theme's again. **/
	public function clearOverrides():Void {
		colorOverrides.clear();
		spacingOverrides.clear();
		radiusOverrides.clear();
		repaint = true;
		relayout = true;
		changed();
	}

	// --- CSS variables ---

	/**
		Every token as a CSS custom property, named without `--`, for style
		sheets: colours with overrides as `#rrggbb` or `rgba(…)`, radii and
		spacing without overrides in `px`, and so on. Names and forms are
		Blinc's, so a sheet written for it reads the same values.
	**/
	public function toCssVariableMap():Map<String, String> {
		var vars = new Map<String, String>();
		function c(name:String, token:ColorToken)
			vars.set(name, cssColor(color(token)));
		c("primary", Primary);
		c("primary-hover", PrimaryHover);
		c("primary-active", PrimaryActive);
		c("secondary", Secondary);
		c("secondary-hover", SecondaryHover);
		c("secondary-active", SecondaryActive);
		c("success", Success);
		c("success-bg", SuccessBg);
		c("warning", Warning);
		c("warning-bg", WarningBg);
		c("error", Error);
		c("error-bg", ErrorBg);
		c("info", Info);
		c("info-bg", InfoBg);
		c("background", Background);
		c("surface", Surface);
		c("surface-elevated", SurfaceElevated);
		c("surface-overlay", SurfaceOverlay);
		c("text-primary", TextPrimary);
		c("text-secondary", TextSecondary);
		c("text-tertiary", TextTertiary);
		c("text-inverse", TextInverse);
		c("text-link", TextLink);
		c("border", Border);
		c("border-secondary", BorderSecondary);
		c("border-hover", BorderHover);
		c("border-focus", BorderFocus);
		vars.set("focus-ring", cssColor(color(BorderFocus).withAlpha(0.35)));
		c("border-error", BorderError);
		vars.set("focus-ring-error", cssColor(color(BorderError).withAlpha(0.35)));
		vars.set("focus-ring-success", cssColor(color(Success).withAlpha(0.35)));
		c("input-bg", InputBg);
		c("input-bg-hover", InputBgHover);
		c("input-bg-focus", InputBgFocus);
		c("input-bg-disabled", InputBgDisabled);
		c("selection", Selection);
		c("selection-text", SelectionText);
		c("accent", Accent);
		c("accent-subtle", AccentSubtle);
		c("tooltip-bg", TooltipBackground);
		c("tooltip-text", TooltipText);

		var r = currentRadii;
		function radius(name:String, v:Float)
			vars.set('radius-$name', px(v));
		radius("none", r.radiusNone);
		radius("sm", r.radiusSm);
		radius("default", r.radiusDefault);
		radius("md", r.radiusMd);
		radius("lg", r.radiusLg);
		radius("xl", r.radiusXl);
		radius("2xl", r.radius2xl);
		radius("3xl", r.radius3xl);
		radius("full", r.radiusFull);

		var s = currentSpacing;
		function space(name:String, v:Float)
			vars.set('space-$name', px(v));
		space("0", s.space0);
		space("0-5", s.space0_5);
		space("1", s.space1);
		space("1-5", s.space1_5);
		space("2", s.space2);
		space("2-5", s.space2_5);
		space("3", s.space3);
		space("3-5", s.space3_5);
		space("4", s.space4);
		space("5", s.space5);
		space("6", s.space6);
		space("7", s.space7);
		space("8", s.space8);
		space("9", s.space9);
		space("10", s.space10);
		space("11", s.space11);
		space("12", s.space12);
		space("14", s.space14);
		space("16", s.space16);
		space("20", s.space20);
		space("24", s.space24);
		space("28", s.space28);
		space("32", s.space32);

		var t = currentTypography;
		vars.set("font-sans", family(t.fontSans));
		vars.set("font-mono", family(t.fontMono));
		vars.set("font-serif", family(t.fontSerif));
		function text(name:String, v:Float)
			vars.set('text-$name', px(v));
		text("xs", t.textXs);
		text("sm", t.textSm);
		text("base", t.textBase);
		text("lg", t.textLg);
		text("xl", t.textXl);
		text("2xl", t.text2xl);
		text("3xl", t.text3xl);
		text("4xl", t.text4xl);
		text("5xl", t.text5xl);
		function weight(name:String, v:FontWeight)
			vars.set('font-$name', Std.string((v : Int)));
		weight("thin", t.fontThin);
		weight("light", t.fontLight);
		weight("normal", t.fontNormal);
		weight("medium", t.fontMedium);
		weight("semibold", t.fontSemibold);
		weight("bold", t.fontBold);
		weight("black", t.fontBlack);
		function leading(name:String, v:Float)
			vars.set('leading-$name', F32.toString(v));
		leading("none", t.leadingNone);
		leading("tight", t.leadingTight);
		leading("snug", t.leadingSnug);
		leading("normal", t.leadingNormal);
		leading("relaxed", t.leadingRelaxed);
		leading("loose", t.leadingLoose);
		function tracking(name:String, v:Float)
			vars.set('tracking-$name', F32.toString(v) + "em");
		tracking("tighter", t.trackingTighter);
		tracking("tight", t.trackingTight);
		tracking("normal", t.trackingNormal);
		tracking("wide", t.trackingWide);
		tracking("wider", t.trackingWider);

		var a = currentAnimations;
		function duration(name:String, v:Int)
			vars.set('duration-$name', '${v}ms');
		duration("fastest", a.durationFastest);
		duration("faster", a.durationFaster);
		duration("fast", a.durationFast);
		duration("normal", a.durationNormal);
		duration("slow", a.durationSlow);
		duration("slower", a.durationSlower);
		duration("slowest", a.durationSlowest);
		function ease(name:String, v:Easing)
			vars.set('ease-$name', easing(v));
		ease("default", a.easeDefault);
		ease("in", a.easeIn);
		ease("out", a.easeOut);
		ease("in-out", a.easeInOut);
		ease("state", a.easeState);
		ease("nav", a.easeNav);
		ease("spring", a.easeSpring);
		ease("sheet", a.easeSheet);
		var sh = currentShadows;
		function shadow(name:String, stack:Array<Shadow>)
			vars.set(name, cssShadow(stack));
		shadow("shadow-sm", sh.shadowSm);
		shadow("shadow", sh.shadowDefault);
		shadow("shadow-md", sh.shadowMd);
		shadow("shadow-lg", sh.shadowLg);
		shadow("shadow-xl", sh.shadowXl);
		shadow("shadow-2xl", sh.shadow2xl);
		shadow("shadow-inner", sh.shadowInner);
		return vars;
	}

	/** A shadow stack as CSS's `box-shadow`: each layer `x y blur spread colour`, `inset` first when inside; `none` for none. **/
	static function cssShadow(stack:Array<Shadow>):String {
		var layers = [
			for (l in stack)
				if (l.color.a > 0 || l.blur > 0 || l.spread != 0)
					(l.inset ? "inset " : "") + '${px(l.offsetX)} ${px(l.offsetY)} ${px(l.blur)} ${px(l.spread)} ${cssColor(l.color)}'
		];
		return layers.length == 0 ? "none" : layers.join(", ");
	}

	/** `c` as CSS: `#rrggbb` when opaque, else `rgba(r,g,b,a)`. **/
	public static function cssColor(c:Rgba):String {
		if (c.a < 1)
			return 'rgba(${c.byte(c.r)},${c.byte(c.g)},${c.byte(c.b)},${F32.toString(c.a)})';
		return "#" + StringTools.hex(c.byte(c.r), 2).toLowerCase() + StringTools.hex(c.byte(c.g), 2).toLowerCase()
			+ StringTools.hex(c.byte(c.b), 2).toLowerCase();
	}

	static function px(v:Float):String {
		var rounded = Math.fround(v);
		return Math.abs(v - rounded) < 1.1920929e-7 ? '${Std.int(rounded)}px' : F32.toString(v) + "px";
	}

	static function family(f:FontFamily):String {
		var names = [f.name].concat(f.fallbacks);
		return [for (n in names) ~/\s/.match(n) ? '"$n"' : n].join(", ");
	}

	static function easing(e:Easing):String {
		var p = Easing.EasingTools.controlPoints(e);
		return p == null ? "linear" : 'cubic-bezier(${[for (v in p) F32.toString(v)].join(", ")})';
	}

	// --- internals ---

	/** Takes `theme`'s tokens; its colours too when `withColors`. **/
	function adopt(theme:Theme, withColors:Bool):Void {
		if (withColors)
			currentColors = theme.colors;
		currentShadows = theme.shadows;
		currentSpacing = theme.spacing;
		currentTypography = theme.typography;
		currentRadii = theme.radii;
		currentShape = theme.shape;
		currentAnimations = theme.animations;
	}

	/** Tells the reactive graph and the redraw callback that tokens changed. **/
	function changed():Void {
		revision.set(revision.get() + 1);
		if (redrawCallback != null)
			redrawCallback();
	}

	inline function locked<T>(f:() -> T):T {
		#if target.threaded
		lock.acquire();
		var result = try f() catch (e:haxe.Exception) {
			lock.release();
			throw e;
		}
		lock.release();
		return result;
		#else
		return f();
		#end
	}

	static var debugSeen:Null<Map<String, Bool>>;

	/** With `ASHUI_DEBUG_COLOR_TOKEN=1`, prints each token and colour pair the first time it is resolved. **/
	static function debugColor(token:ColorToken, value:Rgba):Void {
		if (debugSeen == null) {
			if (Sys.getEnv("ASHUI_DEBUG_COLOR_TOKEN") != "1")
				return;
			debugSeen = new Map();
		}
		var key = '$token ${value.r} ${value.g} ${value.b} ${value.a}';
		if (debugSeen.exists(key))
			return;
		debugSeen.set(key, true);
		Sys.stderr().writeString('[theme.color] $token → (${value.r}, ${value.g}, ${value.b}, ${value.a})\n');
	}
}
