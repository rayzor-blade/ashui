package ashui.css;

import ashui.css.CssValue;
import ashui.css.Selector;
import ashui.css.Stylesheet;
import ashui.layout.LayoutTree;

/** What the cascade left on an element last time: its winning values and the fields they wrote. **/
private typedef Applied = {
	/** Each property's winning value, for inheritance and to skip an unchanged restyle. **/
	final values:Map<String, String>;

	final signature:String;
	final fields:Array<Int>;
}

/**
	The stylesheets in force and how they reach elements.

	`Css.add(sheet)` puts a parsed `Stylesheet` in force (`Css.load` parses
	and adds CSS text). Matching and the cascade run in the native CSS
	engine (`NativeCascade`): every element's types, id, classes,
	attributes, own declarations and tested states go to it, and at the
	next `LayoutTree.flush` it restyles what a change can reach and says
	whose styles changed; those are applied here. A frame that changes no
	structure, class or tested state costs nothing.

	`transition` gives each property it names its own timing, so a change
	the cascade makes moves there (an element's own transition, a Tw class,
	wins over it). `animation` runs `@keyframes` on the animation
	scheduler, its frames interpolated where two values have the same shape
	and switched halfway where they do not; an animated property is the
	animation's while it runs, and with `forwards` after.

	The cascade is CSS's, property by property: `!important` over normal,
	then specificity, then order (a later sheet's rule after an earlier
	sheet's, a later rule after an earlier one). As in Tailwind's layers, a
	stylesheet sits under what an element sets itself: its Tw classes, its
	`style=` and its attributes win over any rule. When no rule sets a
	property any more, it goes back to what a new element has.

	Text inherits `font-size`, `font-weight`, `font-style`, `font-family`,
	`line-height`, `letter-spacing` and `text-align` from the elements
	around it, as CSS's inherited properties do; `color` is inherited by
	drawing. `var(--name, fallback)` reads the custom properties of the
	element and its ancestors, then of `:root` rules, then the theme's
	tokens (`--primary`, `--surface`, `--radius-lg` …; see
	`ThemeState.toCssVariableMap`), following the theme: an element that
	reads a token is matched again when the theme changes, a switch between
	light and dark included.

	A declaration that reads `env(pointer-x)` and the rest is applied again
	as the pointer moves: a pointer query (see `PointerQueries`).

	A rule inside `@media` applies while its queries hold: of the viewport
	`setViewport` gives, and `prefers-color-scheme` of the theme's scheme.

	State pseudo-classes read the element's `Interaction`: `:hover`,
	`:active`, `:focus`, `:focus-visible`, `:focus-within`, `:disabled` and
	`:enabled`, `:checked` and `:indeterminate`, and a form control's
	`:placeholder-shown`, `:valid`, `:invalid`, `:user-valid`,
	`:user-invalid`, `:required` and `:optional`, of the element itself or of
	one a combinator reaches (`.card:hover .title`). An element whose rules
	test a state is matched again when that state changes, and only then.
**/
class Css {
	/** The sheets in force, in order. **/
	static final sheets:Array<Stylesheet> = [];

	/** Problems found applying declarations, each once: an unknown property, a value that does not read. **/
	public static final problems:Array<String> = [];

	/** What `vw` and `vh` are a hundredth of, and what `@media` asks about; see `setViewport`. **/
	public static var viewportWidth(default, null) = 0.0;

	public static var viewportHeight(default, null) = 0.0;

	/**
		The viewport's size in layout units, set by the window and the
		offscreen renderer as it changes. Rules whose `@media` starts or
		stops holding apply or stop at the next flush.
	**/
	public static function setViewport(width:Float, height:Float):Void {
		if (width == viewportWidth && height == viewportHeight)
			return;
		viewportWidth = width;
		viewportHeight = height;
		mediaChanged();
	}

	static function environment():Media.MediaEnvironment {
		var theme = ashui.theme.ThemeState.tryGet();
		return {width: viewportWidth, height: viewportHeight, dark: theme != null && theme.scheme() == Dark};
	}

	/** What `@media` and viewport units read, and the root font size, to the engine. **/
	static function mediaChanged():Void {
		var env = environment();
		sentRootFontSize = rootFontSize;
		NativeCascade.setEnvironment(env.width, env.height, env.dark, rootFontSize);
		ashui.core.Work.notify();
	}

	static var sentRootFontSize = Math.NaN;

	/** What `rem` is, and the font size of text with none of its own. **/
	public static var rootFontSize = 16.0;

	static final pending = new haxe.ds.ObjectMap<LayoutTree, Map<String, Identity>>();
	static final applied = new haxe.ds.ObjectMap<Identity, Applied>();
	static final reported = new Map<String, Bool>();
	static var hooked = false;

	/** Parses `source` and puts it in force; its problems are the returned sheet's `diagnostics`. **/
	public static function load(source:String, ?file:String):Stylesheet {
		var sheet = Stylesheet.parse(source, file);
		add(sheet);
		return sheet;
	}

	/** Files loaded with `loadFile`, by sheet: their path, and the times they and what they import were last changed. **/
	static final files = new haxe.ds.ObjectMap<Stylesheet, {path:String, times:Map<String, Float>}>();

	/**
		Reads the CSS file at `path` and puts it in force. Its problems are in
		the returned sheet's `diagnostics`; `update` reads it again when it
		changes, in a development build.
	**/
	public static function loadFile(path:String):Stylesheet {
		#if sys
		var sheet = Stylesheet.parse(sys.io.File.getContent(path), path);
		files.set(sheet, {path: path, times: times(sheet, path)});
		add(sheet);
		return sheet;
		#else
		throw "Css.loadFile needs a file system";
		#end
	}

	/**
		Once a frame, from the renderer: puts in force the CSS a theme bundle
		brought (`ThemeBundle.withCss`), and with `-D ashui_hot_reload`, reads
		again each loaded file that changed, or that a file it imports did,
		putting the new sheet in the old one's place and printing its
		problems. True if a sheet changed.
	**/
	public static function update():Bool {
		var changedAny = false;
		for (css in ashui.theme.ThemeState.drainPendingStylesheets()) {
			load(css, "theme");
			changedAny = true;
		}
		#if (sys && ashui_hot_reload)
		for (sheet => f in files) {
			var stale = false;
			for (file => time in f.times)
				if (!sys.FileSystem.exists(file) || sys.FileSystem.stat(file).mtime.getTime() != time)
					stale = true;
			if (!stale)
				continue;
			if (!sys.FileSystem.exists(f.path))
				continue;
			var next = Stylesheet.parse(sys.io.File.getContent(f.path), f.path);
			files.remove(sheet);
			files.set(next, {path: f.path, times: times(next, f.path)});
			replace(sheet, next);
			var problems = next.report(f.path);
			Sys.println('[css] reloaded ${f.path}' + (problems == "" ? "" : "\n" + problems));
			changedAny = true;
		}
		#end
		return changedAny;
	}

	static function times(sheet:Stylesheet, path:String):Map<String, Float> {
		var out = new Map<String, Float>();
		#if sys
		for (file in [path].concat(sheet.imports))
			if (sys.FileSystem.exists(file))
				out.set(file, sys.FileSystem.stat(file).mtime.getTime());
		#end
		return out;
	}

	/** Puts `sheet` in force, after those already in force; a property it names that this does not apply is a warning in its `diagnostics`. **/
	public static function add(sheet:Stylesheet):Void {
		unknown(sheet);
		sheets.push(sheet);
		changed();
	}

	static function unknown(sheet:Stylesheet):Void {
		for (d in sheet.declared())
			if (!StringTools.startsWith(d.name, "--") && !Properties.known(d.name) && !MOTION.exists(d.name) && !POINTER.exists(d.name))
				sheet.diagnostics.push({
					severity: Warning,
					message: '${d.name} is not a property this supports',
					line: d.line,
					column: d.column
				});
	}

	/** Takes `sheet` out of force; what only it set goes back. **/
	public static function remove(sheet:Stylesheet):Void {
		if (sheets.remove(sheet))
			changed();
	}

	/** Puts `next` in `previous`'s place, as a reloaded file does, keeping its order. **/
	public static function replace(previous:Stylesheet, next:Stylesheet):Void {
		unknown(next);
		var i = sheets.indexOf(previous);
		if (i < 0)
			sheets.push(next);
		else
			sheets[i] = next;
		changed();
	}

	/** Sheets libraries put in force (see `useLibrary`), by name. **/
	static final libraries = new Map<String, Stylesheet>();

	/**
		Puts a component library's sheet in force once, under the name
		`name`: after the user-agent sheet and libraries before it, before
		every sheet the page loads, so a page's CSS restyles a library's
		components as it does built-in elements. Returns the sheet. A
		library compiles its sheet with `CompiledCss.file`, so it is not
		parsed at run time.
	**/
	public static function useLibrary(name:String, sheet:Stylesheet):Stylesheet {
		var known = libraries.get(name);
		if (known != null)
			return known;
		unknown(sheet);
		libraries.set(name, sheet);
		var at = 0;
		for (i => s in sheets)
			if (s == userAgent || Lambda.has(libraries, s))
				at = i + 1;
		sheets.insert(at, sheet);
		changed();
		return sheet;
	}

	/** Takes every sheet out of force but the user-agent sheet and libraries'. **/
	public static function clear():Void {
		var keep = sheets.filter(s -> s == userAgent || Lambda.has(libraries, s));
		if (sheets.length == keep.length)
			return;
		sheets.resize(0);
		for (s in keep)
			sheets.push(s);
		changed();
	}

	/** The user-agent stylesheet once in force: built-in elements' default looks. **/
	public static var userAgent(default, null):Null<Stylesheet> = null;

	/**
		Puts the user-agent stylesheet (`UserAgent.CSS`) in force, first, so
		every other sheet's rule of equal specificity wins over it, as a
		browser's defaults lose to the page's. Built-in elements call it. The
		sheet was parsed when the program was compiled.
	**/
	public static function useUserAgent():Void {
		if (userAgent != null)
			return;
		userAgent = CompiledCss.userAgent();
		unknown(userAgent);
		sheets.unshift(userAgent);
		changed();
	}

	/** The sheets in force changed: the engine takes them, and restyles every element. **/
	static function changed():Void {
		hook();
		NativeCascade.sync(sheets);
		NativeCascade.setTheme(theme());
		mediaChanged();
	}

	/** `identity`'s computed value of CSS property `name`, inherited ones included, as CSS text; null when it has none. **/
	public static function computed(identity:Identity, name:String):Null<String> {
		var a = applied.get(identity);
		return a == null ? null : a.values.get(name);
	}

	/**
		The elements under `root` in `tree`, `root` included, that one of
		`selectors` matches, in document order: `querySelectorAll`.
	**/
	public static function select(tree:LayoutTree, root:haxe.Int64, selectors:Array<Selector>):Array<haxe.Int64>
		return query(tree, root, [for (s in selectors) s.toString()].join(", "));

	/** As `select`, of selectors written as CSS text; throws for text that does not read. **/
	public static function query(tree:LayoutTree, root:haxe.Int64, selectors:String):Array<haxe.Int64> {
		hook();
		return NativeCascade.select(tree, root, selectors);
	}

	/** `text` with its `var()`s replaced as `identity` would read them: its own and inherited custom properties, `:root`'s, the theme's. **/
	public static function resolve(identity:Identity, text:String):String {
		var a = applied.get(identity);
		return substitute(text, a == null ? new Map() : a.values, identity);
	}

	/** `identity`'s computed value of `name` with its `var()`s replaced; null when it has none. **/
	public static function resolved(identity:Identity, name:String):Null<String> {
		var v = computed(identity, name);
		return v == null ? null : resolve(identity, v);
	}

	/** Called with each element whose styles were applied anew, as text flow measures again when a font changes. **/
	public static final restyled:Array<Identity->Void> = [];

	@:allow(ashui.css.Identity)
	static function hook():Void {
		if (hooked)
			return;
		hooked = true;
		// Every element is described to the engine, those made before now too: one with declarations of its own is styled with no sheet loaded, as Tw's text classes are.
		for (tree => nodes in @:privateAccess Identity.trees)
			for (identity in nodes)
				NativeCascade.describe(identity);
		Identity.hooks.push(identity -> {
			NativeCascade.describe(identity);
			ashui.core.Work.notify();
		});
		Identity.forgetHooks.push(identity -> {
			release(identity);
			NativeCascade.forget(identity);
		});
		LayoutTree.childrenHooks.push((tree, parent) -> {
			NativeCascade.childrenChanged(tree, parent);
			ashui.core.Work.notify();
		});
		LayoutTree.flushHooks.push(flush);
	}

	// --- What to apply again ---

	static function mark(identity:Identity):Void {
		var tree = identity.tree;
		var nodes = pending.get(tree);
		if (nodes == null)
			pending.set(tree, nodes = new Map());
		nodes.set(haxe.Int64.toStr(identity.node.id), identity);
		ashui.core.Work.notify();
	}

	// --- Applying ---

	/** Restyles through the engine and applies what changed, parents first. **/
	static function flush(tree:LayoutTree):Void {
		// Marked to apply again, as an animation that ended hands back to the cascade: applied though the engine saw no change.
		var again = pending.get(tree);
		pending.remove(tree);
		// A theme set since the sheets were, or a root font size since the viewport: the engine takes it.
		if (themeVariables == null && ashui.theme.ThemeState.tryGet() != null)
			NativeCascade.setTheme(theme());
		if (rootFontSize != sentRootFontSize)
			mediaChanged();
		var changed = NativeCascade.restyle(tree);
		if (again != null)
			for (identity in again)
				if (changed.indexOf(identity) < 0 && Identity.of(tree, identity.node.id) == identity)
					changed.push(identity);
		for (identity in changed) {
			var style = NativeCascade.style(identity);
			var up = identity.tree.ancestors(identity.node.id);
			var parent = up.length == 0 ? null : Identity.of(identity.tree, up[0]);
			var fontSize = parent == null ? rootFontSize : NativeCascade.style(parent).fontSize;
			apply(identity, style.resolved, style.values, fontSize, style.fontSize, new Map());
		}
	}

	/**
		Applies `identity`'s resolved declarations: `fontSize` is its parent's,
		`ownFontSize` its own.
	**/
	static function apply(identity:Identity, resolved:Map<String, String>, values:Map<String, String>, fontSize:Float, ownFontSize:Float,
			from:Map<String, Declaration>):Void {
		var node = identity.node.id;
		var signature = [for (name => v in resolved) '$name:$v'];
		signature.sort(Reflect.compare);
		var sig = signature.join(";");
		var last = applied.get(identity);
		if (last != null && last.signature == sig) {
			applied.set(identity, {values: values, signature: sig, fields: last.fields});
			return;
		}

		var ctx:Properties.ApplyContext = {
			viewportWidth: viewportWidth,
			viewportHeight: viewportHeight,
			fontSize: fontSize,
			rootFontSize: rootFontSize,
			glassProperties: resolved,
			currentColor: values.exists("color") ? (try CssValue.color(substitute(values.get("color"), values, identity)) catch (_:String) CurrentColor) : CurrentColor
		};
		// The background frosts over a backdrop-filter's blur, so each reads whether the other is there.
		if (resolved.exists("backdrop-filter")) {
			var blur = try Properties.backdropBlur(resolved.get("backdrop-filter"), ctx) catch (_:String) -1.0;
			ctx = {
				viewportWidth: ctx.viewportWidth,
				viewportHeight: ctx.viewportHeight,
				fontSize: ctx.fontSize,
				rootFontSize: ctx.rootFontSize,
				currentColor: ctx.currentColor,
				backdropBlur: blur,
				glassProperties: ctx.glassProperties,
				hasBackground: resolved.exists("background") || resolved.exists("background-color")
			};
		}
		if (resolved.exists("background-size"))
			ctx = {
				viewportWidth: ctx.viewportWidth,
				viewportHeight: ctx.viewportHeight,
				fontSize: ctx.fontSize,
				rootFontSize: ctx.rootFontSize,
				currentColor: ctx.currentColor,
				backdropBlur: ctx.backdropBlur,
				hasBackground: ctx.hasBackground,
				backgroundSize: resolved.get("background-size"),
				glassProperties: ctx.glassProperties
			};
		var fields:Array<Int> = [];
		// The transition first, so the changes below move by it.
		try {
			if (@:privateAccess identity.node.styleTransition(CssMotion.transition(resolved)) && hasTransition(resolved))
				fields.push(ashui.layout.Node.TRANSITION);
		} catch (e:String) {
			report(from.get("transition"), e);
		}
		// Animations: started, kept running or stopped as the element's animation values change.
		var held = Animations.update(identity, resolved, values, ctx, from);
		// Each field written once, the last write to it: a shorthand then its longhand do not move twice.
		// Declarations that read the pointer are the pointer query's, applied as it moves.
		var live = new Map<String, String>();
		for (name => v in resolved)
			if (!POINTER.exists(name) && !MOTION.exists(name) && (v.indexOf("env(") >= 0 || v.indexOf("pointer-") >= 0))
				live.set(name, v);
		@:privateAccess ashui.layout.Node.restyling = last != null;
		@:privateAccess identity.node.styleAll(() -> {
			// font-size first: em in the rest is the element's own font size.
			var names = [for (name in resolved.keys()) if (!MOTION.exists(name) && !POINTER.exists(name) && !held.exists(name) && !live.exists(name)) name];
			// Shorthands before their longhands, which a stronger rule declared when both are here.
			names.sort((a, b) -> a == "font-size" ? -1 : b == "font-size" ? 1 : Properties.rank(a) != Properties.rank(b) ? Properties.rank(a)
				- Properties.rank(b) : Reflect.compare(a, b));
			for (name in names) {
				var v = resolved.get(name);
				if (!Properties.known(name)) {
					report(from.get(name), '$name is not a property this supports');
					continue;
				}
				try {
					for (f in Properties.apply(identity.node, name, v, ctx))
						fields.push(f);
				} catch (e:String) {
					report(from.get(name), '$name: $e');
				}
				if (name == "font-size")
					ctx = {
						viewportWidth: ctx.viewportWidth,
						viewportHeight: ctx.viewportHeight,
						fontSize: ownFontSize,
						rootFontSize: ctx.rootFontSize,
						currentColor: ctx.currentColor,
						backdropBlur: ctx.backdropBlur,
						hasBackground: ctx.hasBackground,
						backgroundSize: ctx.backgroundSize,
						glassProperties: ctx.glassProperties
					};
			}
		});
		@:privateAccess ashui.layout.Node.restyling = false;
		var pointer = try PointerQueries.config(resolved) catch (e:String) {
			report(from.get("pointer-range"), e);
			null;
		}
		PointerQueries.track(identity, pointer, live, ctx, from);
		for (f in PointerQueries.fields(identity))
			if (fields.indexOf(f) < 0)
				fields.push(f);
		// What an animation writes stays its own until it ends.
		for (f in Animations.fields(identity))
			if (fields.indexOf(f) < 0)
				fields.push(f);
		if (last != null)
			for (f in last.fields)
				if (fields.indexOf(f) < 0)
					@:privateAccess identity.node.unstyle(f);
		applied.set(identity, {values: values, signature: sig, fields: fields});
		for (hook in restyled)
			hook(identity);

	}

	/** The motion properties, applied as a transition and animations rather than one by one. **/
	static final MOTION = [
		for (name in ["transition", "transition-property", "transition-duration", "transition-timing-function", "transition-delay", "animation", "animation-name",
			"animation-duration", "animation-timing-function", "animation-delay", "animation-iteration-count", "animation-direction",
			"animation-fill-mode", "animation-play-state"])
			name => true
	];

	/** A pointer query's settings, read by the tracker rather than applied. **/
	static final POINTER = ["pointer-space" => true, "pointer-origin" => true, "pointer-range" => true, "pointer-smoothing" => true];

	static function hasTransition(values:Map<String, String>):Bool
		return values.exists("transition") || values.exists("transition-property");

	/** The `@keyframes` named `name`, the last sheet's that defines it. **/
	@:allow(ashui.css.Animations)
	static function keyframes(name:String):Null<Keyframes>
		return NativeCascade.keyframes(name);

	/** Matches `identity` again and applies what the cascade gives in full, as when an animation hands its properties back. **/
	@:allow(ashui.css.Animations)
	static function markAgain(identity:Identity):Void {
		var last = applied.get(identity);
		if (last != null)
			applied.set(identity, {values: last.values, signature: "", fields: last.fields});
		mark(identity);
	}

	@:allow(ashui.css.Animations)
	static function problem(d:Null<Declaration>, message:String):Void
		report(d, message);

	/** The theme's variables, made again when the theme changes. **/
	static var themeVariables:Null<Map<String, String>> = null;

	static var themeWatched = false;

	static function theme():Map<String, String> {
		if (themeVariables != null)
			return themeVariables;
		var state = try ashui.theme.ThemeState.get() catch (_:Dynamic) null;
		// Nothing kept before there is a theme: the first restyle after one is set reads it.
		if (state == null)
			return new Map();
		if (!themeWatched) {
			themeWatched = true;
			new ashui.reactive.Watch(() -> state.revision.get(), _ -> {
				themeVariables = null;
				NativeCascade.setTheme(theme());
				mediaChanged();
			});
		}
		return themeVariables = state.toCssVariableMap();
	}

	/** `var(--name, fallback)` replaced by the element's custom property, then `:root`'s, then the theme's, then the fallback. **/
	static function substitute(value:String, values:Map<String, String>, ?reader:Identity):String {
		// Each pass replaces every var() in the value; passes go on while what replaced them holds more, ten deep at most, so a
		// variable that names itself ends rather than loops.
		var depth = 0;
		while (value.indexOf("var(") >= 0 && depth++ < 10) {
			var out = new StringBuf();
			var from = 0;
			while (true) {
				var at = value.indexOf("var(", from);
				if (at < 0)
					break;
				var nesting = 0, end = at + 4;
				while (end < value.length) {
					var c = value.charAt(end);
					if (c == "(")
						nesting++;
					else if (c == ")") {
						if (nesting == 0)
							break;
						nesting--;
					}
					end++;
				}
				var args = value.substring(at + 4, end);
				var comma = args.indexOf(",");
				var name = StringTools.trim(comma < 0 ? args : args.substr(0, comma));
				var fallback = comma < 0 ? null : StringTools.trim(args.substr(comma + 1));
				var found = values.get(name);
				if (found == null)
					found = NativeCascade.rootVariable(name.substr(2));
				if (found == null) {
					found = theme().get(name.substr(2));
				}
				if (found == null)
					found = fallback == null ? "" : fallback;
				out.add(value.substring(from, at));
				out.add(found);
				from = end + 1;
			}
			out.add(value.substr(from));
			value = out.toString();
		}
		return value;
	}

	static function pixelsOr(v:String, fallback:Float):Float {
		return try CssValue.resolve(CssValue.length(v), {
			percentOf: fallback,
			fontSize: fallback,
			rootFontSize: rootFontSize,
			viewportWidth: viewportWidth,
			viewportHeight: viewportHeight
		}) catch (_:String) fallback;
	}

	static function report(d:Null<Declaration>, message:String):Void {
		var where = d == null ? "" : '${d.line}:${d.column}: ';
		var line = where + message;
		if (reported.exists(line))
			return;
		reported.set(line, true);
		problems.push(line);
	}

	/** Lets go of everything kept for a removed element: what was applied, its tracker and animations. **/
	static function release(identity:Identity):Void {
		applied.remove(identity);
		PointerQueries.track(identity, null, [], null, []);
		Animations.release(identity);
	}

}
