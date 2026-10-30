package ashui.ui;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import tink.hxx.Attribute;
import tink.hxx.Node;
import tink.hxx.Parser;

using haxe.macro.ComplexTypeTools;
using haxe.macro.ExprTools;
using haxe.macro.TypeTools;
#end

/**
	Compiles HXX templates into typed element construction and property bindings.
	`Markup.enable()` lets applications write elements directly in Haxe code.
	This class also provides the underlying `hxx` template macro.

	Tags use kebab case: `<my-card>` resolves to an imported `MyCard` component;
	`<ui.my-card>` names `ui.MyCard`. Component attributes are checked against
	its props. `<div>` and `<text>` compile to constructors and direct property
	writes. `bg` maps to `Prop.Background`; other attributes map by name.
	Inline `<svg>` content is parsed and checked at compile time.

	Styling applies in this order: utility classes, `style`, then explicit
	attributes. See `ashui.style.Tw`.

	Signals and computeds create bindings. Attribute expressions that read
	reactive values become computeds automatically. For component props,
	this requires `IntoReactive<T>`. Text interpolation reads signals and
	computeds; element and element-array interpolation inserts children.
	Bare text inside a `<div>` becomes a `<text>` element.

	`<if {cond}>...<else>...</if>` creates a `Show`.
	`<for {v in list}>...</for>` creates a `For`. Branches or loop bodies
	with multiple elements receive a `<div>` wrapper. All elements use
	the current owner's tree.
**/
class Hxx {
	public static macro function hxx(template:Expr):Expr {
		var children = Parser.parseRoot(template, {
			defaultExtension: 'hxx',
			treatNested: nested -> {
				// 66cc2f7: the parser finds nested markup before a comprehension's
				// variables are in scope. Lower it when the compiler types its body.
				var index = nestedTemplates.length;
				if (index == 0)
					Context.onAfterGenerate(() -> nestedTemplates.resize(0));
				nestedTemplates.push(nested);
				macro @:pos(nested.pos) ashui.ui.Hxx.nestedMarkup($v{index});
			},
		});
		return single(elements(children), template.pos);
	}

	/** Internal entry point for markup inside an embedded Haxe expression. **/
	@:noCompletion public static macro function nestedMarkup(index:Int):Expr {
		var children = nestedTemplates[index];
		return single(elements(children), children.pos);
	}

	#if macro
	static var counter = 0;
	static final nestedTemplates:Array<Children> = [];

	/** Loop variables in scope where the template is being lowered. **/
	static var locals:Array<{name:String, type:ComplexType}> = [];

	/** Resolves an expression type with enclosing loop variables in scope. Returns null when typing fails. **/
	static function typeOf(e:Expr):Null<Type> {
		var scoped = e;
		for (local in locals) {
			var name = local.name, type = local.type;
			scoped = macro {
				var $name:$type = cast null;
				$scoped;
			};
		}
		return try Context.typeof(scoped) catch (_:Dynamic) null;
	}

	/** Compiles a template containing one element. **/
	static function single(nodes:Array<Piece>, pos:Position):Expr {
		return switch nodes {
			case [One(e)]: e;
			case []: Context.error('hxx: the template is empty', pos);
			case [Many(e)]: Context.error('hxx: a template\'s root is one element, not an array', e.pos);
			case _: Context.error('hxx: a template has exactly one root element', pos);
		}
	}

	/** Compiles branch or loop content, grouping multiple elements in a fragment `Div`. **/
	static function group(nodes:Array<Piece>, pos:Position):Expr {
		return switch nodes {
			case [One(e)]: e;
			case []: Context.error('hxx: this body is empty', pos);
			// A fragment, so the body's elements are laid out in the element it is placed in, as one would be.
			case _: macro @:pos(pos) {
					var body = new ashui.ui.Div(null, null);
					body.tree.makeFragment(body.node.id);
					for (child in ${childArray(nodes)})
						body.appendChild(child);
					body;
				};
		}
	}

	/** Builds one `Array<Element>` expression for the children. **/
	static function childArray(nodes:Array<Piece>):Expr {
		var result:Null<Expr> = null;
		var ones:Array<Expr> = [];
		function append(e:Expr)
			result = result == null ? e : macro $result.concat($e);
		for (node in nodes)
			switch node {
				case One(e):
					ones.push(e);
				case Many(e):
					if (ones.length > 0)
						append(macro($a{ones} : Array<ashui.layout.Element>));
					ones = [];
					append(e);
			}
		if (ones.length > 0 || result == null)
			append(macro($a{ones} : Array<ashui.layout.Element>));
		return result;
	}

	/** Converts node children into element expressions. **/
	static function elements(children:Children):Array<Piece> {
		var out:Array<Piece> = [];
		if (children == null)
			return out;
		var run:Array<Child> = [];
		function endText() {
			if (run.length > 0)
				out.push(One(textElement(run, [], run[0].pos)));
			run = [];
		}
		for (child in children.value)
			switch child.value {
				case CNode(node):
					endText();
					out.push(One(lowerNode(node)));
				case CText(_):
					run.push(child);
				case CExpr(e):
					switch placement(e) {
						case null:
							run.push(child);
						case piece:
							endText();
							out.push(piece);
					}
				case CIf(cond, cons, alt):
					endText();
					var then = group(elements(cons), child.pos);
					var otherwise = alt == null || alt.value.length == 0 ? macro null : macro() -> ${group(elements(alt), alt.pos)};
					out.push(One(macro @:pos(child.pos) new ashui.ui.Show(() -> ${read(cond)}, () -> $then, $otherwise)));
				case CFor(head, body):
					endText();
					switch head.expr {
						case EBinop(OpIn, {expr: EConst(CIdent(name))}, list):
							var each = read(list);
							var valueType = switch typeOf(each) {
								case null: Context.error('hxx: cannot type this list', list.pos);
								case t: switch Context.follow(t) {
										case TInst(_.get() => {pack: [], name: 'Array'}, [v]): v.toComplexType();
										case _: Context.error('hxx: <for> needs an array, or a signal or computed of one', list.pos);
									}
							}
							locals.push({name: name, type: valueType});
							var item = try group(elements(body), child.pos) catch (e:Dynamic) {
								locals.pop();
								throw e;
							}
							locals.pop();
							out.push(One(macro @:pos(child.pos) new ashui.ui.For(() -> $each, ($name:$valueType) -> $item)));
						case _:
							Context.error('hxx: a for loop is <for {value in list}>', head.pos);
					}
				case CSplat(e):
					Context.error('hxx: spreading children is not supported', e.pos);
				case CLet(_, _) | CSwitch(_, _):
					Context.error('hxx: <let> and <switch> are not supported', child.pos);
			}
		endText();
		return out;
	}

	/** Returns an element insertion for an interpolation, or null for text content. **/
	static function placement(e:Expr):Null<Piece> {
		var type = typeOf(e);
		if (type == null)
			return null;
		if (Context.unify(type, Context.getType('ashui.layout.Element')))
			return One(e);
		// Arrays are invariant: an Array<Div> does not unify with Array<Element>, so check what it holds.
		switch Context.follow(type) {
			case TInst(_.get() => {pack: [], name: 'Array'}, [item]) if (Context.unify(item, Context.getType('ashui.layout.Element'))):
				return Many(macro @:pos(e.pos) (cast $e : Array<ashui.layout.Element>));
			case _:
		}
		return null;
	}

	static function lowerNode(node:Node):Expr {
		var tag = node.name.value;
		if (~/[A-Z]/.match(tag))
			Context.error('hxx: tags are lowercase kebab-case: write <${kebab(tag)}>', node.name.pos);
		// An imported component of a built-in element's name wins over it, as an import does in JSX.
		if (tag != 'div' && importedComponent(tag))
			return lowerComponent(node);
		return switch tag {
			case 'div': lowerDiv(node);
			case t if (TEXT_TAGS.indexOf(t) >= 0): lowerDiv(node, t);
			case t if (BOX_TAGS.indexOf(t) >= 0): lowerDiv(node, t);
			case 'pre':
				// Its text keeps its lines as written, wrapping nowhere.
				preformatted++;
				var e = lowerDiv(node, 'pre');
				preformatted--;
				e;
			case 'text': textElement(node.children == null ? [] : node.children.value, node.attributes, node.name.pos);
			case 'svg': lowerSvg(node);
			case 'img': lowerImg(node);
			case _: lowerComponent(node);
		}
	}

	/** Returns whether an attribute can be applied to a component root as a `Div` property. **/
	static function rootAttribute(name:String):Bool {
		if (name == "hidden" || name == "title")
			return true;
		var key = name == 'bg' ? 'Background' : name.charAt(0).toUpperCase() + name.substr(1);
		return (try Context.typeof(macro ashui.layout.Prop.$key) catch (_:Dynamic) null) != null;
	}

	/** Returns whether a tag resolves to a visible component outside the built-in `ashui.ui` elements. **/
	static function importedComponent(tag:String):Bool {
		var type = try Context.getType(className(tag)) catch (_:Dynamic) null;
		if (type == null)
			return false;
		return switch type {
			case TInst(c, _): c.get().pack.join(".") != "ashui.ui" && componentProps(type) != null;
			case _: false;
		}
	}

	/** Converts a class name to kebab-case HXX, preserving package names. **/
	static function kebab(name:String):String {
		var parts = name.split('.');
		var last = ~/([a-z0-9])([A-Z])/g.replace(parts.pop(), '$1-$2');
		last = ~/([A-Z])([A-Z][a-z])/g.replace(last, '$1-$2');
		parts.push(last.toLowerCase());
		return parts.join('.');
	}

	/** Resolves a tag to a class name: `my-card` becomes `MyCard`, and `ui.my-card` becomes `ui.MyCard`. **/
	static function className(tag:String):String {
		var parts = tag.split('.');
		var last = [
			for (word in parts.pop().split('-')) word.charAt(0).toUpperCase() + word.substr(1)
		].join('');
		parts.push(last);
		return parts.join('.');
	}

	/**
		Builds class assignments: utility styles first, then declared CSS classes
		on the element identity.
	**/
	static function classSetters(value:Expr, el:String):Array<Expr> {
		var css = [];
		var sets = ashui.style.Tw.setters(value, macro $i{el}.node, css);
		if (css.length > 0)
			sets.unshift(macro @:pos(value.pos) ashui.css.Identity.of($i{el}.tree, $i{el}.node.id).setClasses($v{css}));
		return sets;
	}

	/** Builds an element ID assignment for CSS `#id` selectors. **/
	static function idSetter(value:Expr, el:String):Expr
		return macro @:pos(value.pos) ashui.css.Identity.of($i{el}.tree, $i{el}.node.id).setId(($value : String));

	/**
		Built-in text tags styled by the user-agent stylesheet, including heading
		size, emphasis weight, and code fonts.
	**/
	static final TEXT_TAGS = [
		"h1", "h2", "h3", "h4", "h5", "h6", "p", "span", "strong", "b", "em", "i", "small", "code", "kbd", "mark", "s", "u", "ins", "del", "abbr", "output"
	];

	/** Built-in box tags without additional behavior. **/
	static final BOX_TAGS = [
		"button",
		"hr",
		"br",
		"legend",
		"blockquote",
		"caption",
		"thead",
		"tbody",
		"tfoot",
		"tr",
		"dl",
		"dt",
		"dd",
		"figure",
		"figcaption",
		"section",
		"article",
		"aside",
		"header",
		"footer",
		"nav",
		"main"
	];

	/** Tags whose text and inline children share one text flow. See `ashui.text.InlineFlow`. **/
	static final FLOW_TAGS = [
		"p",
		"h1",
		"h2",
		"h3",
		"h4",
		"h5",
		"h6",
		"dt",
		"dd",
		"caption",
		"legend",
		"figcaption"
	];

	/** Nesting depth inside `<pre>`, where text does not wrap. **/
	static var preformatted = 0;

	/** Built-in tags whose class names differ from their tag names. **/
	static final BUILT_IN_CLASSES = [
		"a" => "Anchor",
		"textarea" => "TextArea",
		"ul" => "Lists.Ul",
		"ol" => "Lists.Ol",
		"colgroup" => "Table.Colgroup",
		"col" => "Table.Col",
		"td" => "Table.Td",
		"th" => "Table.Th"
	];

	static function lowerDiv(node:Node, ?tag:String):Expr {
		var el = '__div${counter++}';
		var kids = childArray(elements(node.children));
		// Classes first, then a style, then the element's own attributes, each winning over the last.
		var classes = [], styles = [], own = [];
		for (a in node.attributes)
			switch a {
				case Regular(name, value) if (name.value == 'class'):
					classes = classes.concat(classSetters(value, el));
				case Regular(name, value) if (name.value == 'id'):
					own.push(idSetter(value, el));
				case Regular(name, value)
					if ((['type', 'name', 'value'].indexOf(name.value) >= 0 && tag == 'button')
						|| ((name.value == 'for' || name.value == 'name') && tag == 'output')):
					own.push(macro @:pos(value.pos) ashui.css.Identity.of($i{el}.tree, $i{el}.node.id).setAttribute($v{name.value}, ($value : String)));
				case Regular(name, value) if (name.value == 'style'):
					styles.push(macro @:pos(value.pos) ($value : ashui.style.Style).apply($i{el}.node));
				case _:
					own.push(setter(el, a, '<div>'));
			}
		// A button takes focus from Tab and a press, as HTML's does.
		if (tag == 'button' && !Lambda.exists(node.attributes, a -> switch a {
			case Regular(name, _) | Empty(name): name.value == 'focusable';
			case _: false;
		}))
			own.unshift(macro ashui.input.Interaction.of($i{el}.node).setFocusable(true));
		var sets = classes.concat(styles).concat(own);
		// Its text and inline elements flow as one paragraph.
		if (tag != null && FLOW_TAGS.indexOf(tag) >= 0)
			sets.push(macro ashui.text.InlineFlow.attach($i{el}));
		var attr = tag == null ? macro null : macro {tag: $v{tag}};
		return macro @:pos(node.name.pos) {
			var $el = new ashui.ui.Div($attr, $kids);
			$b{sets};
			$i{el};
		};
	}

	/**
		Compiles an image from its `src` bitmap. `fit` and `object-*` utilities
		control fitting and positioning; the default is fill. Other classes,
		styles, and attributes apply to the image element normally.
	**/
	static function lowerImg(node:Node):Expr {
		var el = '__img${counter++}';
		var src:Null<Expr> = null;
		var fit:Null<Expr> = null;
		var position:Null<Expr> = null;
		var classes = [], styles = [], own = [];
		for (a in node.attributes)
			switch a {
				case Regular(name, value) if (name.value == 'src'):
					src = value;
				case Regular(name, value) if (name.value == 'fit'):
					fit = value;
				case Regular(name, value) if (name.value == 'objectPosition'):
					position = value;
				case Regular(name, value) if (name.value == 'class'):
					var text = switch value.expr {
						case EConst(CString(s, _)): s;
						case _: Context.error("hxx: <img>'s class must be a string literal", value.pos);
					}
					classes = classes.concat(classSetters({expr: EConst(CString(text)), pos: value.pos}, el));
				case Regular(name, value) if (name.value == 'id'):
					own.push(idSetter(value, el));
				case Regular(name, value) if (name.value == 'style'):
					styles.push(macro @:pos(value.pos) ($value : ashui.style.Style).apply($i{el}.node));
				case _:
					own.push(setter(el, a, '<img>'));
			}
		if (src == null)
			Context.error("hxx: <img> needs src={bitmap}", node.name.pos);
		var sets = classes.concat(styles).concat(own);
		if (fit == null)
			fit = macro null;
		if (position == null)
			position = macro null;
		var attributes = macro {fit: $fit, objectPosition: $position};
		return macro @:pos(node.name.pos) {
			var $el = new ashui.ui.Image($src, $attributes);
			$b{sets};
			$i{el};
		};
	}

	/**
		Parses inline SVG at compile time. Quoted attributes and child markup
		belong to the SVG document. On the outer element, `class` and expression
		values for `style`, `width`, `height`, and `color` configure the Ashui element.
	**/
	static function lowerSvg(node:Node):Expr {
		var el = '__svg${counter++}';
		var classes = [], styles = [], own = [];
		var xml = Xml.createElement('svg');
		for (a in node.attributes)
			switch a {
				case Regular(name, _) if (name.value == "hidden" || name.value == "title"):
					own.push(setter(el, a, '<svg>'));
				case Regular(name, value) if (name.value == 'class'):
					classes = classes.concat(classSetters(value, el));
				case Regular(name, {expr: EConst(CString(text))}):
					xml.set(name.value, text);
				case Regular(name, value) if (name.value == 'style'):
					styles.push(macro @:pos(value.pos) ($value : ashui.style.Style).apply($i{el}.node));
				case Regular(name, _) if (['width', 'height', 'color', 'ref'].indexOf(name.value) >= 0):
					own.push(setter(el, a, '<svg>'));
				case Regular(name, value):
					Context.error('hxx: <svg> takes "${name.value}" only as a quoted value', value.pos);
				case _:
					own.push(setter(el, a, '<svg>'));
			}
		svgChildren(node, xml);
		var doc = ashui.svg.SvgDocument.compileXml(xml, node.name.pos);
		var sets = classes.concat(styles).concat(own);
		return macro @:pos(node.name.pos) {
			var $el = new ashui.ui.Svg($doc);
			$b{sets};
			$i{el};
		};
	}

	/** Copies nested SVG children into the XML document. **/
	static function svgChildren(node:Node, xml:Xml):Void {
		if (node.children == null)
			return;
		for (child in node.children.value)
			switch child.value {
				case CNode(n):
					var e = Xml.createElement(n.name.value);
					for (a in n.attributes)
						switch a {
							case Regular(name, {expr: EConst(CString(text))}):
								e.set(name.value, text);
							case Regular(name, value):
								Context.error('hxx: inside <svg>, "${name.value}" takes only a quoted value', value.pos);
							case Empty(name):
								Context.error('hxx: attribute "${name.value}" needs a value', name.pos);
							case Splat(e):
								Context.error('hxx: spreading attributes is not supported', e.pos);
						}
					svgChildren(n, e);
					xml.addChild(e);
				case CText(text):
					// Text content: what `<text>` shows, a `<style>` sheet.
					xml.addChild(Xml.createPCData(text.value));
				case _:
					Context.error('hxx: inside <svg>, only SVG elements and text', child.pos);
			}
	}

	/** Builds a text element from text, interpolations, and attributes. **/
	static function textElement(parts:Array<Child>, attributes:Array<Attribute>, pos:Position):Expr {
		var el = '__text${counter++}';
		var pieces:Array<Expr> = [];
		var reactive = false;
		for (part in parts)
			switch part.value {
				case CText(text):
					pieces.push(macro @:pos(text.pos) $v{text.value});
				case CExpr(e):
					var read = readValue(e);
					reactive = reactive || read.reactive;
					pieces.push(read.expr);
				case _:
					Context.error('hxx: a Text holds only text and interpolations', part.pos);
			}
		var content = macro "";
		for (piece in pieces)
			content = macro $content + $piece;
		if (reactive)
			content = macro ashui.reactive.Computed.make(() -> ($content : String));

		var options = [];
		if (preformatted > 0 && !Lambda.exists(attributes, a -> a.match(Regular({value: 'wrap'}, _))))
			options.push({field: 'wrap', expr: macro false});
		var classes = [], styles = [], own = [];
		for (a in attributes)
			switch a {
				case Regular(name, value) if (name.value == 'wrap'):
					options.push({field: 'wrap', expr: value});
				case Regular(name, value) if (name.value == 'class'):
					classes = classes.concat(classSetters(value, el));
				case Regular(name, value) if (name.value == 'id'):
					own.push(idSetter(value, el));
				case Regular(name, value) if (name.value == 'style'):
					styles.push(macro @:pos(value.pos) ($value : ashui.style.Style).apply($i{el}.node));
				case _:
					own.push(setter(el, a, '<text>'));
			}
		var sets = classes.concat(styles).concat(own);
		var attr = options.length == 0 ? macro null : {expr: EObjectDecl(options), pos: pos};
		return macro @:pos(pos) {
			var $el = new ashui.ui.Text($content, $attr);
			$b{sets};
			$i{el};
		};
	}

	/** Builds a typed component constructor with props and children. **/
	static function lowerComponent(node:Node):Expr {
		var tag = node.name.value;
		// A built-in element's class is ashui.ui's, needing no import.
		var builtIn = BUILT_IN_CLASSES.exists(tag) ? BUILT_IN_CLASSES.get(tag) : className(tag);
		var type = try Context.getType(className(tag)) catch (_:Dynamic) try
			Context.getType("ashui.ui." + builtIn)
		catch (_:Dynamic)
			Context.error('hxx: unknown tag <$tag>', node.name.pos);
		var cls = switch type {
			case TInst(c, _): c.get();
			case _: Context.error('hxx: <$tag> is not a class', node.name.pos);
		}
		var props = switch componentProps(type) {
			case null: Context.error('hxx: <$tag> is not an ashui.ui.Component', node.name.pos);
			case p: p;
		}
		var propTypes = switch Context.follow(props) {
			case TAnonymous(a): [for (f in a.get().fields) f.name => f.type];
			case _: Context.error('hxx: <$tag>\'s props are not a structure', node.name.pos);
		}
		// Attributes the component does not take go to its root element, as a <div>'s do: class adds classes, style and layout attributes bind.
		var el = '__component${counter++}';
		var rootSets:Array<Expr> = [];
		var fields = [];
		for (a in node.attributes)
			switch a {
				case Regular(name, value):
					// HTML's for, a Haxe keyword, is the htmlFor prop.
					var field = name.value == "for" ? "htmlFor" : name.value;
					var propType = propTypes.get(field);
					if (propType != null) {
						fields.push({field: field, expr: propValue(value, propType)});
						continue;
					}
					switch name.value {
						case 'class':
							var css = [];
							var sets = ashui.style.Tw.setters(value, macro $i{el}.node, css);
							if (css.length > 0)
								sets.unshift(macro @:pos(value.pos) ashui.css.Identity.of($i{el}.tree, $i{el}.node.id).addClasses($v{css}));
							rootSets = rootSets.concat(sets);
						case 'style':
							rootSets.push(macro @:pos(value.pos) ($value : ashui.style.Style).apply($i{el}.node));
						case 'ref':
							rootSets.push(refSetter(value, el));
						case n if (inputSetter(el, n, value) != null || rootAttribute(n) || n == 'animateLayout' || n == 'notch'):
							rootSets.push(setter(el, a, '<$tag>'));
						case _:
							Context.error('hxx: <$tag> has no prop "${name.value}"', name.pos);
					}
				case Empty(name):
					if (name.value == "hidden" && !propTypes.exists(name.value)) {
						rootSets.push(setter(el, a, '<$tag>'));
						continue;
					}
					if (!propTypes.exists(name.value))
						Context.error('hxx: <$tag> has no prop "${name.value}"', name.pos);
					fields.push({field: name.value, expr: macro @:pos(name.pos) true});
				case Splat(e):
					Context.error('hxx: spreading attributes is not supported', e.pos);
			}
		var module = cls.module.split('.').pop();
		var path:TypePath = module == cls.name ? {pack: cls.pack, name: cls.name} : {pack: cls.pack, name: module, sub: cls.name};
		var propsExpr:Expr = {expr: EObjectDecl(fields), pos: node.name.pos};
		var kids = childArray(elements(node.children));
		var made:Expr = {expr: ENew(path, [propsExpr, kids]), pos: node.name.pos};
		if (rootSets.length == 0)
			return made;
		return macro @:pos(node.name.pos) {
			var $el = $made;
			$b{rootSets};
			$i{el};
		};
	}



	/** The tags HXX knows without an import, as fields of `HxxTags`, for completion after `<`. **/
	public static function tagFields():Array<Field> {
		var names = ["div", "text", "pre", "svg", "img"];
		for (list in [TEXT_TAGS, BOX_TAGS, [for (k in BUILT_IN_CLASSES.keys()) k]])
			for (n in list)
				if (names.indexOf(n) < 0)
					names.push(n);
		names.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
		return [
			for (n in names)
				{
					name: n,
					access: [APublic],
					kind: FVar(macro :Bool),
					pos: Context.currentPos(),
					doc: 'The <$n> element.'
				}
		];
	}

	/**
		The type an attribute list of `tag` is checked against, for completion: the props of a component,
		or the attributes of a box for a built-in element; null for a tag that names nothing.
	**/
	public static function attributeType(tag:String):Null<ComplexType> {
		if (tag == "div" || tag == "text" || tag == "pre" || tag == "svg" || tag == "img" || TEXT_TAGS.indexOf(tag) >= 0 || BOX_TAGS.indexOf(tag) >= 0)
			return macro :ashui.ui.Div.DivAttributes;
		var builtIn = BUILT_IN_CLASSES.exists(tag) ? BUILT_IN_CLASSES.get(tag) : className(tag);
		var type = try Context.getType(className(tag)) catch (_:Dynamic) try
			Context.getType("ashui.ui." + builtIn)
		catch (_:Dynamic)
			null;
		if (type == null)
			return null;
		var props = componentProps(type);
		return props == null ? null : Context.toComplexType(props);
	}

	/** Resolves the props type of a `Component<Props>` subclass, or null. **/
	static function componentProps(type:Type):Null<Type> {
		var current = switch type {
			case TInst(c, _): c.get().superClass;
			case _: null;
		}
		while (current != null) {
			var cls = current.t.get();
			if (cls.pack.join('.') == 'ashui.ui' && cls.name == 'Component')
				return current.params[0];
			current = cls.superClass;
		}
		return null;
	}

	/** Builds a prop value, adding reactive binding for `IntoReactive<T>`. **/
	static function propValue(value:Expr, propType:Type):Expr {
		return switch propType {
			case TAbstract(_.get() => {pack: [], name: 'Null'}, [inner]): propValue(value, inner);
			case TAbstract(_.get() => {pack: ['ashui', 'layout'], name: 'IntoReactive'}, [inner]): bindable(value, inner);
			case TType(_, _) | TLazy(_): propValue(value, Context.follow(propType, true));
			case _: value;
		}
	}

	/** Supported handler attributes and their event types. **/
	static final HANDLERS = [
		"onClick" => "PointerEvent",
		"onPointerDown" => "PointerEvent",
		"onPointerUp" => "PointerEvent",
		"onPointerMove" => "PointerEvent",
		"onPointerEnter" => "PointerEvent",
		"onPointerLeave" => "PointerEvent",
		"onWheel" => "PointerEvent",
		"onTouchStart" => "TouchEvent",
		"onTouchMove" => "TouchEvent",
		"onTouchEnd" => "TouchEvent",
		"onTouchCancel" => "TouchEvent",
		"onKeyDown" => "KeyEvent",
		"onKeyUp" => "KeyEvent",
		"onTextInput" => "TextInputEvent",
		"onFocus" => "FocusEvent",
		"onBlur" => "FocusEvent",
		"onComposition" => "CompositionEvent"
	];

	/**
		Binds handlers, `focusable`, and `disabled` to the node interaction.
		Handlers may accept an event argument or no argument.
	**/
	static function inputSetter(el:String, name:String, value:Expr):Null<Expr> {
		var interaction = macro ashui.input.Interaction.of($i{el}.node);
		var event = HANDLERS.get(name);
		if (event != null) {
			var eventType = TPath({pack: ['ashui', 'input'], name: 'Events', sub: event});
			var handler = switch (try Context.follow(Context.typeof(value)) catch (_:Dynamic) null) {
				case TFun([], _): macro @:pos(value.pos) (_ -> $value() : $eventType->Void);
				case _: macro @:pos(value.pos) ($value : $eventType->Void);
			}
			return macro @:pos(value.pos) $interaction.$name($handler);
		}
		return switch name {
			case 'focusable': macro @:pos(value.pos) $interaction.setFocusable($value);
			case 'disabled':
				var bound = bindable(value, Context.getType('Bool'));
				macro @:pos(value.pos) $interaction.setDisabled($bound);
			case _: null;
		}
	}

	/** Binds a typed HXX reference. A reference to a different element type is a compile error. **/
	static function refSetter(value:Expr, el:String):Expr
		return macro @:pos(value.pos) $value.bind($i{el});

	/** Builds a node property or input-handler assignment for an attribute. **/
	static function setter(el:String, attribute:Attribute, tag:String):Expr {
		return switch attribute {
			case Regular(name, value) if (name.value == "hidden"):
				var bound = bindable(value, Context.getType("Bool"));
				macro @:pos(value.pos) ashui.css.Identity.of($i{el}.tree, $i{el}.node.id).bindBooleanAttribute("hidden", $bound);
			case Empty(name) if (name.value == "hidden"):
				macro @:pos(name.pos) ashui.css.Identity.of($i{el}.tree, $i{el}.node.id).bindBooleanAttribute("hidden", true);
			case Regular(name, value) if (name.value == "title"):
				var bound = bindable(value, Context.getType("String"));
				macro @:pos(value.pos) ashui.css.Identity.of($i{el}.tree, $i{el}.node.id).bindAttribute("title", $bound);
			case Regular(name, value) if (name.value == 'ref'):
				refSetter(value, el);
			case Regular(name, value) if (inputSetter(el, name.value, value) != null):
				inputSetter(el, name.value, value);
			case Regular(name, value) if (name.value == 'notch' && tag == '<div>'):
				macro @:pos(value.pos) ashui.ui.Div.bindNotch($i{el}, $value);
			case Regular(name, value) if (name.value == 'animateLayout'):
				macro @:pos(value.pos) if (($value : Bool)) ashui.animation.LayoutAnimation.attach($i{el}.node);
			case Regular(name, value):
				var key = name.value == 'bg' ? 'Background' : name.value.charAt(0).toUpperCase() + name.value.substr(1);
				var keyExpr = macro @:pos(name.pos) ashui.layout.Prop.$key;
				var valueType = switch (try Context.typeof(keyExpr) catch (_:Dynamic) null) {
					case TAbstract(_, [t]): t;
					case _: Context.error('hxx: $tag has no attribute "${name.value}"', name.pos);
				}
				var bound = bindable(value, valueType);
				macro @:pos(value.pos) $i{el}.node.set($keyExpr, $bound);
			case Empty(name):
				Context.error('hxx: attribute "${name.value}" needs a value', name.pos);
			case Splat(e):
				Context.error('hxx: spreading attributes is not supported', e.pos);
		}
	}

	/** Converts an attribute value to a constant, signal binding, or computed binding. **/
	static function bindable(value:Expr, valueType:Type):Expr {
		var type = typeOf(value);
		if (type != null && isReactive(type))
			return value;
		if (reads(value)) {
			var ct = valueType.toComplexType();
			return macro @:pos(value.pos) ashui.reactive.Computed.make(() -> ($value : $ct));
		}
		return value;
	}

	/** Reads reactive values used as conditions or lists in `Show` and `For`. **/
	static function read(e:Expr):Expr {
		var type = typeOf(e);
		return type != null && isReactive(type) ? macro @:pos(e.pos) $e.get() : e;
	}

	/** Builds a string interpolation and reports whether it reads reactive state. **/
	static function readValue(e:Expr):{expr:Expr, reactive:Bool} {
		var type = typeOf(e);
		if (type != null && isReactive(type))
			return {expr: macro @:pos(e.pos) $e.get(), reactive: true};
		return {expr: e, reactive: reads(e)};
	}

	/** Detects signal reads through `.get()` or component `@:state` fields. **/
	static function reads(e:Expr):Bool {
		return callsGet(e) || readsState(e);
	}

	static function readsState(e:Expr):Bool {
		var names = [];
		var cls = Context.getLocalClass();
		var current = cls == null ? null : cls.get();
		while (current != null) {
			for (f in current.fields.get())
				if (f.meta.has(':state'))
					names.push(f.name);
			current = current.superClass == null ? null : current.superClass.t.get();
		}
		if (names.length == 0)
			return false;
		var shadowed = [for (local in locals) local.name];
		var found = false;
		function visit(e:Expr)
			switch e.expr {
				case EConst(CIdent(name)) if (names.contains(name) && !shadowed.contains(name)):
					found = true;
				case EField({expr: EConst(CIdent('this'))}, name) if (names.contains(name)):
					found = true;
				case EFunction(_, _): // a nested function reads when it is called, not here
				case _:
					e.iter(visit);
			}
		visit(e);
		return found;
	}

	static function callsGet(e:Expr):Bool {
		var found = false;
		function visit(e:Expr)
			switch e.expr {
				case ECall({expr: EField(_, 'get')}, []):
					found = true;
				case EFunction(_, _): // a nested function reads when it is called, not here
				case _:
					e.iter(visit);
			}
		visit(e);
		return found;
	}

	static function isReactive(type:Type):Bool {
		return switch type {
			case TAbstract(_.get() => {pack: ['ashui', 'reactive'], name: 'Signal' | 'Computed'}, _): true;
			case TInst(_, _): Context.unify(type,
					(macro :ashui.reactive.ISignal<Dynamic>).toType()) || Context.unify(type, (macro :ashui.reactive.IComputed<Dynamic>).toType());
			case TType(_, _) | TLazy(_): isReactive(Context.follow(type, true));
			case _: false;
		}
	}
	#end
}

#if macro
/** A single child element or an array inserted into the child list. **/
private enum Piece {
	One(e:Expr);
	Many(e:Expr);
}
#end
