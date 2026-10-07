package ashui.css;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
#end

/**
	Stylesheets parsed when the program is compiled rather than when it
	starts. The macros run `CssParser` over the CSS and return the parsed
	`Stylesheet` as typed literals, so at run time only its objects are
	built and nothing is parsed. Parse errors are compile errors, and
	warnings compile warnings, at their line in the CSS file.

	```haxe
	Css.useLibrary("my-library", CompiledCss.file("../css/library.css"));
	```

	`Css.useUserAgent` and `ashui.components.Library` use these. A page's
	own sheets, loaded with `Css.load` or `Css.loadFile`, are still parsed
	at run time, so live reload keeps working.
**/
class CompiledCss {
	/**
		The CSS file at `path`, relative to the file calling this, parsed now.
		The program is compiled again when the file, or one it imports,
		changes.
	**/
	public static macro function file(path:String):ExprOf<Stylesheet> {
		var caller = Context.getPosInfos(Context.currentPos()).file;
		var full = haxe.io.Path.isAbsolute(path) ? path : haxe.io.Path.join([haxe.io.Path.directory(sys.FileSystem.fullPath(caller)), path]);
		full = haxe.io.Path.normalize(full);
		if (!sys.FileSystem.exists(full))
			Context.error('CompiledCss: no file $full', Context.currentPos());
		var source = sys.io.File.getContent(full);
		var sheet = Stylesheet.parse(source, full);
		report(sheet, full, source);
		DeclaredCss.include(sheet);
		Context.registerModuleDependency(Context.getLocalModule(), full);
		for (imported in sheet.imports)
			Context.registerModuleDependency(Context.getLocalModule(), imported);
		return emit(sheet);
	}

	/** The user-agent stylesheet, `UserAgent.CSS`, parsed now. **/
	public static macro function userAgent():ExprOf<Stylesheet> {
		var sheet = Stylesheet.parse(UserAgent.CSS, "user-agent.css");
		for (d in sheet.diagnostics)
			if (d.severity == Error)
				Context.error('user-agent.css:${d.line}:${d.column}: ${d.message}', Context.currentPos());
		return emit(sheet);
	}

	#if macro
	/** Reports a sheet's diagnostics as compile errors and warnings, at their place in the CSS. **/
	static function report(sheet:Stylesheet, file:String, source:String):Void
		for (d in sheet.diagnostics) {
			// A problem in an imported file is reported in that file.
			var where = d.file == null ? file : d.file;
			var text = d.file == null ? source : sys.io.File.getContent(d.file);
			var pos = position(where, text, d.line, d.column);
			if (d.severity == Error)
				Context.error('css: ${d.message}', pos);
			else
				Context.warning('css: ${d.message}', pos);
		}

	static function position(file:String, source:String, line:Int, column:Int):Position {
		var offset = 0;
		for (_ in 1...line) {
			var next = source.indexOf("\n", offset);
			if (next < 0)
				break;
			offset = next + 1;
		}
		offset += column - 1;
		return Context.makePosition({min: offset, max: offset + 1, file: file});
	}

	/** An expression that builds `sheet` at run time from literals. **/
	static function emit(sheet:Stylesheet):Expr {
		var rules = [for (r in sheet.rules) rule(r)];
		var variables = [for (k => v in sheet.variables) macro $v{k} => $v{v}];
		var keyframes = [];
		for (k => v in sheet.keyframes) {
			var frames = [];
			for (f in v.frames) {
				var declarations = f.declarations.map(declaration);
				frames.push(macro {offsets: $v{f.offsets}, declarations: [$a{declarations}]});
			}
			keyframes.push(macro $v{k} => {name: $v{v.name}, frames: [$a{frames}]});
		}
		var variablesExpr = variables.length > 0 ? macro [$a{variables}] : macro new Map<String, String>();
		var keyframesExpr = keyframes.length > 0 ? macro [$a{keyframes}] : macro new Map<String, ashui.css.Stylesheet.Keyframes>();
		return macro ashui.css.Stylesheet.of([$a{rules}], $variablesExpr, $keyframesExpr, $v{sheet.imports});
	}

	static function rule(r:Stylesheet.StyleRule):Expr {
		var media = macro null;
		if (r.media != null) {
			var lists = [];
			for (list in r.media) {
				var queries = list.map(query);
				lists.push(macro [$a{queries}]);
			}
			media = macro [$a{lists}];
		}
		return macro ({
			selectors: [$a{r.selectors.map(selector)}],
			declarations: [$a{r.declarations.map(declaration)}],
			media: $media,
			order: $v{r.order},
			line: $v{r.line}
		} : ashui.css.Stylesheet.StyleRule);
	}

	static function declaration(d:Stylesheet.Declaration):Expr
		return macro ({
			name: $v{d.name},
			value: $v{d.value},
			important: $v{d.important},
			line: $v{d.line},
			column: $v{d.column}
		} : ashui.css.Stylesheet.Declaration);

	static function selector(s:Selector):Expr {
		var leading = s.leading == null ? macro null : combinator(s.leading);
		return macro new ashui.css.Selector([$a{s.compounds.map(compound)}], [$a{s.combinators.map(combinator)}], $leading);
	}

	static function compound(c:Selector.Compound):Expr {
		var attributes = [for (a in c.attributes) macro {name: $v{a.name}, op: $v{a.op}, value: $v{a.value}}];
		return macro ashui.css.Selector.Compound.of($v{c.type}, $v{c.id}, $v{c.classes}, [$a{attributes}], [$a{c.pseudos.map(pseudo)}], $v{c.pseudoElement});
	}

	static function combinator(c:Selector.Combinator):Expr
		return switch c {
			case Descendant: macro ashui.css.Selector.Combinator.Descendant;
			case Child: macro ashui.css.Selector.Combinator.Child;
			case NextSibling: macro ashui.css.Selector.Combinator.NextSibling;
			case LaterSibling: macro ashui.css.Selector.Combinator.LaterSibling;
		}

	static function nth(n:Selector.Nth):Expr
		return macro {a: $v{n.a}, b: $v{n.b}};

	static function pseudo(p:Selector.Pseudo):Expr
		return switch p {
			case State(name): macro ashui.css.Selector.Pseudo.State($v{name});
			case Root: macro ashui.css.Selector.Pseudo.Root;
			case Empty: macro ashui.css.Selector.Pseudo.Empty;
			case FirstChild: macro ashui.css.Selector.Pseudo.FirstChild;
			case LastChild: macro ashui.css.Selector.Pseudo.LastChild;
			case OnlyChild: macro ashui.css.Selector.Pseudo.OnlyChild;
			case NthChild(n): macro ashui.css.Selector.Pseudo.NthChild(${nth(n)});
			case NthLastChild(n): macro ashui.css.Selector.Pseudo.NthLastChild(${nth(n)});
			case FirstOfType: macro ashui.css.Selector.Pseudo.FirstOfType;
			case LastOfType: macro ashui.css.Selector.Pseudo.LastOfType;
			case OnlyOfType: macro ashui.css.Selector.Pseudo.OnlyOfType;
			case NthOfType(n): macro ashui.css.Selector.Pseudo.NthOfType(${nth(n)});
			case NthLastOfType(n): macro ashui.css.Selector.Pseudo.NthLastOfType(${nth(n)});
			case Not(s): macro ashui.css.Selector.Pseudo.Not([$a{s.map(selector)}]);
			case Is(s): macro ashui.css.Selector.Pseudo.Is([$a{s.map(selector)}]);
			case Where(s): macro ashui.css.Selector.Pseudo.Where([$a{s.map(selector)}]);
			case Has(s): macro ashui.css.Selector.Pseudo.Has([$a{s.map(selector)}]);
		}

	static function query(q:Media.MediaQuery):Expr
		return macro ({not: $v{q.not}, features: [$a{q.features.map(feature)}]} : ashui.css.Media.MediaQuery);

	static function compare(c:Media.Compare):Expr
		return switch c {
			case Eq: macro ashui.css.Media.Compare.Eq;
			case Lt: macro ashui.css.Media.Compare.Lt;
			case Le: macro ashui.css.Media.Compare.Le;
			case Gt: macro ashui.css.Media.Compare.Gt;
			case Ge: macro ashui.css.Media.Compare.Ge;
		}

	static function feature(f:Media.MediaFeature):Expr
		return switch f {
			case Width(op, px): macro ashui.css.Media.MediaFeature.Width(${compare(op)}, $v{px});
			case Height(op, px): macro ashui.css.Media.MediaFeature.Height(${compare(op)}, $v{px});
			case AspectRatio(op, ratio): macro ashui.css.Media.MediaFeature.AspectRatio(${compare(op)}, $v{ratio});
			case Orientation(portrait): macro ashui.css.Media.MediaFeature.Orientation($v{portrait});
			case ColorScheme(dark): macro ashui.css.Media.MediaFeature.ColorScheme($v{dark});
			case Fixed(holds): macro ashui.css.Media.MediaFeature.Fixed($v{holds});
			case Both(a, b): macro ashui.css.Media.MediaFeature.Both(${feature(a)}, ${feature(b)});
		}
	#end
}
