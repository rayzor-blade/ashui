package ashui.css;

import ashui.css.CssValue;
import ashui.css.Selector;
import ashui.css.Stylesheet;
import ashui.layout.LayoutTree;

private typedef Matched = {
	final declaration:Declaration;
	final important:Bool;
	final specificity:Int;
	final sheet:Int;
	final order:Int;
	final index:Int;
}

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
	and adds CSS text). Every element is then matched against its rules:
	when it is made, when a sheet is added or removed, when its classes or
	id change, and when the children of an element above or beside it
	change, at the next `LayoutTree.flush`. Nothing is re-matched
	otherwise, so a frame that changes no structure or class costs nothing.

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

	/** Which `@media` rules hold, as a string, to tell when one flips. **/
	static var mediaState = "";

	static function environment():Media.MediaEnvironment {
		var theme = ashui.theme.ThemeState.tryGet();
		return {width: viewportWidth, height: viewportHeight, dark: theme != null && theme.scheme() == Dark};
	}

	static function mediaChanged():Void {
		var env = environment();
		var state = new StringBuf();
		for (sheet in sheets)
			for (rule in sheet.rules)
				if (rule.media != null)
					state.add(Media.allHold(rule.media, env) ? "1" : "0");
		var next = state.toString();
		if (next == mediaState)
			return;
		mediaState = next;
		for (tree => nodes in @:privateAccess Identity.trees)
			for (identity in nodes)
				mark(identity);
	}

	/** What `rem` is, and the font size of text with none of its own. **/
	public static var rootFontSize = 16.0;

	static final pending = new haxe.ds.ObjectMap<LayoutTree, Map<String, Identity>>();
	static final applied = new haxe.ds.ObjectMap<Identity, Applied>();
	static final reported = new Map<String, Bool>();
	static var hooked = false;

	/** Rules by their subject's id, class, type, or none of those, for each sheet. **/
	static var index:Array<{ids:Map<String, Array<Entry>>, classes:Map<String, Array<Entry>>, types:Map<String, Array<Entry>>, rest:Array<Entry>}> = [];

	static var usesHas = false;

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
		for (rule in sheet.rules)
			for (d in rule.declarations)
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

	static function changed():Void {
		hook();
		mediaState = "";
		index = [for (sheet in sheets) indexOf(sheet)];
		theme();
		usesHas = Lambda.exists(sheets, s -> Lambda.exists(s.rules, r -> Lambda.exists(r.selectors, hasHas)));
		// Every element, to be matched again.
		for (tree => nodes in @:privateAccess Identity.trees)
			for (identity in nodes)
				mark(identity);
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
	public static function select(tree:LayoutTree, root:haxe.Int64, selectors:Array<Selector>):Array<haxe.Int64> {
		var walk = new TreeWalk(tree);
		var out = [];
		function visit(node:haxe.Int64) {
			var identity = Identity.of(tree, node);
			if (identity != null && !identity.anonymous) {
				walk.subject = identity;
				for (s in selectors)
					if (walk.matches(s, node)) {
						out.push(node);
						break;
					}
			}
			for (child in tree.children(node))
				visit(child);
		}
		visit(root);
		return out;
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
		// An element with declarations of its own is styled with no sheet loaded, as Tw's text classes are.
		Identity.hooks.push(identity -> if (sheets.length > 0 || applied.exists(identity) || identity.inlineDeclarations() != null)
			markChanged(identity));
		Identity.forgetHooks.push(release);
		LayoutTree.childrenHooks.push((tree, parent) -> if (sheets.length > 0) markSubtree(tree, parent));
		LayoutTree.flushHooks.push(flush);
	}

	// --- What to match again ---

	static function mark(identity:Identity):Void {
		var tree = identity.tree;
		var nodes = pending.get(tree);
		if (nodes == null)
			pending.set(tree, nodes = new Map());
		nodes.set(haxe.Int64.toStr(identity.node.id), identity);
	}

	/**
		An element whose classes, id or attributes changed: it, and what a
		combinator can reach from it, everything under it (`.a .b`, `.a > .b`)
		and its later siblings and theirs (`.a + .b`, `.a ~ .b`).
	**/
	static function markChanged(identity:Identity):Void {
		var tree = identity.tree, node = identity.node.id;
		markSubtree(tree, node);
		var up = tree.ancestors(node);
		if (up.length == 0)
			return;
		var later = false;
		for (sibling in tree.children(up[0]))
			if (later)
				markSubtree(tree, sibling);
			else if (sibling == node)
				later = true;
	}

	/** `parent` and everything under it, and with `:has()` in force, its ancestors. **/
	static function markSubtree(tree:LayoutTree, parent:haxe.Int64):Void {
		var stack = [parent];
		while (stack.length > 0) {
			var at = stack.pop();
			var identity = Identity.of(tree, at);
			if (identity != null)
				mark(identity);
			for (child in tree.children(at))
				stack.push(child);
		}
		if (usesHas)
			for (up in tree.ancestors(parent)) {
				var identity = Identity.of(tree, up);
				if (identity != null)
					mark(identity);
			}
	}

	// --- Applying ---

	static function flush(tree:LayoutTree):Void {
		var nodes = pending.get(tree);
		if (nodes == null)
			return;
		pending.remove(tree);
		var walk = new TreeWalk(tree);
		// Parents first, so a child inherits what its parent has now.
		var list = [for (identity in nodes) identity];
		var depth = new Map<String, Int>();
		for (identity in list)
			depth.set(haxe.Int64.toStr(identity.node.id), walk.ancestors(identity.node.id).length);
		list.sort((a, b) -> depth.get(haxe.Int64.toStr(a.node.id)) - depth.get(haxe.Int64.toStr(b.node.id)));
		for (identity in list)
			if (Identity.of(tree, identity.node.id) == identity)
				restyle(identity, walk);
	}

	static function restyle(identity:Identity, walk:TreeWalk):Void {
		var node = identity.node.id;
		walk.subject = identity;
		var env = environment();
		// The declarations of every rule that matches, in cascade order.
		var matched:Array<Matched> = [];
		for (s => entries in index)
			for (entry in candidates(entries, identity)) {
				if (entry.rule.media != null && !Media.allHold(entry.rule.media, env))
					continue;
				if (!walk.matches(entry.selector, node))
					continue;
				for (i => d in entry.rule.declarations)
					matched.push({
						declaration: d,
						important: d.important,
						specificity: entry.selector.specificity(),
						sheet: s,
						order: entry.rule.order,
						index: i
					});
			}
		matched.sort((a, b) -> a.important != b.important ? (a.important ? 1 : -1) : a.specificity != b.specificity ? a.specificity
			- b.specificity : a.sheet != b.sheet ? a.sheet - b.sheet : a.order != b.order ? a.order - b.order : a.index - b.index);
		// The same declaration may come from two selectors of one rule; the last stands.
		var own = new Map<String, String>();
		var from = new Map<String, Declaration>();
		// Its inline declarations stand over every rule but an !important one, which the sort put last.
		var declared = identity.inlineDeclarations();
		var inlined = false;
		function applyInline() {
			inlined = true;
			if (declared != null)
				for (name => value in declared) {
					var covered = Properties.LONGHANDS.get(name);
					if (covered != null)
						for (l in covered) {
							own.remove(l);
							from.remove(l);
						}
					own.set(name, value);
					from.remove(name);
				}
		}
		for (m in matched) {
			if (m.important && !inlined)
				applyInline();
			// A shorthand sets its longhands anew, over what weaker rules declared of them.
			var covered = Properties.LONGHANDS.get(m.declaration.name);
			if (covered != null)
				for (l in covered) {
					own.remove(l);
					from.remove(l);
				}
			own.set(m.declaration.name, m.declaration.value);
			from.set(m.declaration.name, m.declaration);
		}
		if (!inlined)
			applyInline();

		// What it inherits from its parent, under its own.
		var parent = walk.parent(node);
		var inherited:Null<Applied> = null;
		if (parent != null) {
			var p = Identity.of(identity.tree, parent);
			if (p != null)
				inherited = applied.get(p);
		}
		var values = new Map<String, String>();
		if (inherited != null)
			for (name => v in inherited.values)
				if (INHERITED.indexOf(name) >= 0 || StringTools.startsWith(name, "--"))
					values.set(name, v);
		for (name => v in own)
			values.set(name, v);

		// Variables first, so declarations that read them see them.
		var resolved = new Map<String, String>();
		var text = identity.types.indexOf("text") >= 0;
		for (name => v in values) {
			if (StringTools.startsWith(name, "--"))
				continue;
			// Inherited font properties reach text alone; other elements take only their own.
			if (!own.exists(name) && !text)
				continue;
			resolved.set(name, substitute(v, values, identity));
		}
		// The parent's font-size is passed down computed, in pixels; this element's too, before an unchanged restyle returns.
		var fontSize = rootFontSize;
		if (inherited != null && inherited.values.exists("font-size"))
			fontSize = pixelsOr(inherited.values.get("font-size"), rootFontSize);
		var ownFontSize = fontSize;
		if (resolved.exists("font-size")) {
			ownFontSize = pixelsOr(resolved.get("font-size"), fontSize);
			values.set("font-size", '${ownFontSize}px');
		}
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

		// Inherited values changed: the children inherit again.
		if (last == null || inheritedSignature(last.values) != inheritedSignature(values))
			for (child in walk.children(node)) {
				var c = Identity.of(identity.tree, child);
				if (c != null)
					restyle(c, walk);
			}
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
	static function keyframes(name:String):Null<Keyframes> {
		var found:Null<Keyframes> = null;
		for (sheet in sheets) {
			var k = sheet.keyframes.get(name);
			if (k != null)
				found = k;
		}
		return found;
	}

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

	static final INHERITED = ["color", "font-size", "font-weight", "font-style", "font-family", "line-height", "letter-spacing", "text-align", "white-space"];

	static function inheritedSignature(values:Map<String, String>):String {
		var out = [for (name => v in values) if (INHERITED.indexOf(name) >= 0 || StringTools.startsWith(name, "--")) '$name:$v'];
		out.sort(Reflect.compare);
		return out.join(";");
	}

	/** The theme's variables, made again when the theme changes. **/
	static var themeVariables:Null<Map<String, String>> = null;

	/** Elements that read a theme variable, matched again when the theme changes. **/
	static final themeDependents = new haxe.ds.ObjectMap<Identity, Bool>();

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
				for (d in themeDependents.keys())
					mark(d);
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
					for (sheet in sheets) {
						var v = sheet.variables.get(name.substr(2));
						if (v != null)
							found = v;
					}
				if (found == null) {
					found = theme().get(name.substr(2));
					if (found != null && reader != null)
						themeDependents.set(reader, true);
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

	// --- Rule index ---

	static function indexOf(sheet:Stylesheet) {
		var ids = new Map<String, Array<Entry>>(), classes = new Map<String, Array<Entry>>(), types = new Map<String, Array<Entry>>();
		var rest:Array<Entry> = [];
		function add(map:Map<String, Array<Entry>>, key:String, e:Entry) {
			var list = map.get(key);
			if (list == null)
				map.set(key, list = []);
			list.push(e);
		}
		for (rule in sheet.rules)
			for (selector in rule.selectors) {
				var e:Entry = {rule: rule, selector: selector};
				var subject = selector.subject;
				if (subject.id != null)
					add(ids, subject.id, e);
				else if (subject.classes.length > 0)
					add(classes, subject.classes[0], e);
				else if (subject.type != null)
					add(types, subject.type, e);
				else
					rest.push(e);
			}
		return {ids: ids, classes: classes, types: types, rest: rest};
	}

	static function candidates(index:{ids:Map<String, Array<Entry>>, classes:Map<String, Array<Entry>>, types:Map<String, Array<Entry>>, rest:Array<Entry>},
			identity:Identity):Array<Entry> {
		var out = index.rest.copy();
		if (identity.id != null && index.ids.exists(identity.id))
			out = out.concat(index.ids.get(identity.id));
		for (c in identity.classes())
			if (index.classes.exists(c))
				out = out.concat(index.classes.get(c));
		for (t in identity.types)
			if (index.types.exists(t))
				out = out.concat(index.types.get(t));
		return out;
	}

	/** Watches on element states, by node and state, and the identities matched again when one changes. **/
	static final stateWatches = new Map<String, Array<Identity>>();

	static final stateWatchers = new Map<String, ashui.reactive.Watch<Bool>>();

	/** Lets go of everything kept for a removed element: what was applied, what it depends on, its tracker and animations. **/
	static function release(identity:Identity):Void {
		applied.remove(identity);
		themeDependents.remove(identity);
		var prefix = haxe.Int64.toStr(identity.node.id) + ":";
		for (key => deps in stateWatches) {
			deps.remove(identity);
			// The node's own states, or states no one depends on any more.
			if (deps.length == 0 || StringTools.startsWith(key, prefix)) {
				var w = stateWatchers.get(key);
				if (w != null)
					w.stop();
				stateWatchers.remove(key);
				stateWatches.remove(key);
			}
		}
		PointerQueries.track(identity, null, [], null, []);
		Animations.release(identity);
	}

	/** `subject` depends on `signal`, a state of the node `node`: it is matched again when the state changes. **/
	@:allow(ashui.css.TreeWalk)
	static function dependOn(node:haxe.Int64, state:String, signal:ashui.reactive.Signal<Bool>, subject:Identity):Void {
		var key = haxe.Int64.toStr(node) + ":" + state;
		var deps = stateWatches.get(key);
		if (deps == null) {
			var list:Array<Identity> = [];
			deps = list;
			stateWatches.set(key, deps);
			stateWatchers.set(key, new ashui.reactive.Watch(() -> signal.get(), _ -> for (d in list) mark(d)));
		}
		if (deps.indexOf(subject) < 0)
			deps.push(subject);
	}

	static function hasHas(s:Selector):Bool
		return Lambda.exists(s.compounds, c -> Lambda.exists(c.pseudos, p -> switch p {
			case Has(_): true;
			case Not(inner) | Is(inner) | Where(inner): Lambda.exists(inner, hasHas);
			case _: false;
		}));
}

private typedef Entry = {
	final rule:StyleRule;
	final selector:Selector;
}

/** Selector matching over a tree, caching what it asks the tree. **/
private class TreeWalk {
	final tree:LayoutTree;

	/** The element being matched, which depends on any state a selector tests. **/
	public var subject:Null<Identity> = null;
	final up = new Map<String, Array<haxe.Int64>>();
	final down = new Map<String, Array<haxe.Int64>>();

	public function new(tree:LayoutTree)
		this.tree = tree;

	public function ancestors(node:haxe.Int64):Array<haxe.Int64> {
		var k = haxe.Int64.toStr(node);
		var a = up.get(k);
		if (a == null)
			up.set(k, a = tree.ancestors(node));
		return a;
	}

	public function children(node:haxe.Int64):Array<haxe.Int64> {
		var k = haxe.Int64.toStr(node);
		var c = down.get(k);
		if (c == null)
			down.set(k, c = tree.children(node));
		return c;
	}

	public function parent(node:haxe.Int64):Null<haxe.Int64> {
		var a = ancestors(node);
		return a.length == 0 ? null : a[0];
	}

	/** `node` and its siblings, those a layout added aside (see `Identity.anonymous`). **/
	function siblings(node:haxe.Int64):Array<haxe.Int64> {
		var p = parent(node);
		if (p == null)
			return [node];
		return [
			for (c in children(p)) {
				var identity = c == node ? null : Identity.of(tree, c);
				if (identity == null || !identity.anonymous)
					c;
			}
		];
	}

	/** Whether `selector` matches `node` as its subject. **/
	public function matches(selector:Selector, node:haxe.Int64):Bool
		return at(selector, selector.compounds.length - 1, node, null);

	/**
		Whether compound `i` of `selector` matches `node`, and the compounds
		before it match where its combinators say, right to left; in a
		`:has()` argument, the first compound must also stand to `anchor` as
		its leading combinator says.
	**/
	function at(selector:Selector, i:Int, node:haxe.Int64, anchor:Null<haxe.Int64>):Bool {
		if (!compound(selector.compounds[i], node))
			return false;
		if (i == 0)
			return anchor == null || related(anchor, node, selector.leading == null ? Descendant : selector.leading);
		switch selector.combinators[i - 1] {
			case Child:
				var p = parent(node);
				return p != null && at(selector, i - 1, p, anchor);
			case Descendant:
				for (a in ancestors(node))
					if (at(selector, i - 1, a, anchor))
						return true;
				return false;
			case NextSibling:
				var s = siblings(node);
				var k = s.indexOf(node);
				return k > 0 && at(selector, i - 1, s[k - 1], anchor);
			case LaterSibling:
				var s = siblings(node);
				var k = s.indexOf(node);
				for (j in 0...Std.int(Math.max(0, k)))
					if (at(selector, i - 1, s[j], anchor))
						return true;
				return false;
		}
	}

	/** Whether `node` stands to `anchor` as `how` says: inside it, its child, the next sibling or a later one. **/
	function related(anchor:haxe.Int64, node:haxe.Int64, how:Combinator):Bool {
		return switch how {
			case Descendant: ancestors(node).indexOf(anchor) >= 0;
			case Child: parent(node) == anchor;
			case NextSibling:
				var s = siblings(node);
				var k = s.indexOf(node);
				k > 0 && s[k - 1] == anchor;
			case LaterSibling:
				var s = siblings(node);
				var k = s.indexOf(node);
				var j = s.indexOf(anchor);
				j >= 0 && j < k;
		}
	}

	function compound(c:Compound, node:haxe.Int64):Bool {
		var identity = Identity.of(tree, node);
		if (identity == null)
			return false;
		if (c.type != null && identity.types.indexOf(c.type) < 0)
			return false;
		if (c.id != null && identity.id != c.id)
			return false;
		for (name in c.classes)
			if (!identity.hasClass(name))
				return false;
		for (a in c.attributes)
			if (!attribute(identity.attribute(a.name), a.op, a.value))
				return false;
		if (c.pseudoElement != null)
			return false;
		for (p in c.pseudos)
			if (!pseudo(p, node, identity))
				return false;
		return true;
	}

	/** Whether an attribute's value `v` (null when it has none) passes `[name op value]`. **/
	static function attribute(v:Null<String>, op:Null<String>, want:Null<String>):Bool {
		if (v == null)
			return false;
		return switch op {
			case null: true;
			case "=": v == want;
			case "~=": v.split(" ").indexOf(want) >= 0;
			case "|=": v == want || StringTools.startsWith(v, want + "-");
			case "^=": want != "" && StringTools.startsWith(v, want);
			case "$=": want != "" && StringTools.endsWith(v, want);
			case "*=": want != "" && v.indexOf(want) >= 0;
			case _: false;
		}
	}

	function pseudo(p:Pseudo, node:haxe.Int64, identity:Identity):Bool {
		inline function index(of:Array<haxe.Int64>):Int
			return of.indexOf(node) + 1;
		inline function ofType(list:Array<haxe.Int64>):Array<haxe.Int64> {
			var type = identity.types[0];
			return list.filter(n -> {
				var other = Identity.of(tree, n);
				other != null && other.types[0] == type;
			});
		}
		return switch p {
			case State(name): state(name, identity);
			case Root:
				tree.root != null ? tree.root.id == node : parent(node) == null;
			case Empty: children(node).length == 0;
			case FirstChild: index(siblings(node)) == 1;
			case LastChild:
				var s = siblings(node);
				index(s) == s.length;
			case OnlyChild: siblings(node).length == 1;
			case NthChild(n): nth(n, index(siblings(node)));
			case NthLastChild(n):
				var s = siblings(node);
				nth(n, s.length - index(s) + 1);
			case FirstOfType: index(ofType(siblings(node))) == 1;
			case LastOfType:
				var s = ofType(siblings(node));
				index(s) == s.length;
			case OnlyOfType: ofType(siblings(node)).length == 1;
			case NthOfType(n): nth(n, index(ofType(siblings(node))));
			case NthLastOfType(n):
				var s = ofType(siblings(node));
				nth(n, s.length - index(s) + 1);
			case Not(list): !Lambda.exists(list, s -> matches(s, node));
			case Is(list) | Where(list): Lambda.exists(list, s -> matches(s, node));
			case Has(list): Lambda.exists(list, s -> has(s, node));
		}
	}

	/** Whether `identity`'s element is in state `name` now; the element being matched is matched again when it changes. **/
	function state(name:String, identity:Identity):Bool {
		var interaction = ashui.input.Interaction.of(identity.node);
		var signal = switch name {
			case "hover": interaction.hovered;
			case "active": interaction.pressed;
			case "focus": interaction.focused;
			case "focus-visible": interaction.focusVisible;
			case "focus-within": interaction.focusWithin;
			case "checked": interaction.checked;
			case "indeterminate": interaction.indeterminate;
			case n if (Selector.FORM_STATES.indexOf(n) >= 0): interaction.formState(n);
			case _: interaction.disabled;
		}
		if (subject != null)
			@:privateAccess Css.dependOn(identity.node.id, name, signal, subject);
		var on = signal.get();
		return name == "enabled" ? !on : on;
	}

	/** Whether an element related to `anchor` as `selector`'s leading combinator says matches it. **/
	function has(selector:Selector, anchor:haxe.Int64):Bool {
		var last = selector.compounds.length - 1;
		var how = selector.leading == null ? Descendant : selector.leading;
		var candidates:Array<haxe.Int64> = switch how {
			case NextSibling | LaterSibling:
				var s = siblings(anchor);
				var k = s.indexOf(anchor);
				var after = s.slice(k + 1);
				var out = [];
				for (n in after)
					for (d in subtree(n))
						out.push(d);
				out;
			case _:
				var out = subtree(anchor);
				out.shift();
				out;
		}
		for (n in candidates)
			if (at(selector, last, n, anchor))
				return true;
		return false;
	}

	function subtree(node:haxe.Int64):Array<haxe.Int64> {
		var out = [];
		var stack = [node];
		while (stack.length > 0) {
			var n = stack.pop();
			out.push(n);
			var c = children(n);
			var i = c.length;
			while (i-- > 0)
				stack.push(c[i]);
		}
		return out;
	}

	/** Whether position `i`, from 1, is `a·k + b` for some k ≥ 0. **/
	static function nth(n:Nth, i:Int):Bool {
		if (i < 1)
			return false;
		if (n.a == 0)
			return i == n.b;
		var k = (i - n.b) / n.a;
		return k >= 0 && k == Math.ffloor(k);
	}
}
