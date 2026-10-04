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
	Templates lowered at compile time:

	    hxx('<div width={w} bg={color}><text>Value: ${count}</text></div>')

	`<svg>` is SVG, written as it is: it is parsed and checked at compile
	time and becomes an `Svg` element (see `lowerSvg`).

	Tags are lowercase kebab-case. `<div>` and `<text>` become their
	constructor plus one `node.set(Prop.X, v)` per attribute, with no
	attribute object; `bg` is `Prop.Background` and any other name is the key
	of that name, capitalised. Any other tag names a `Component` class by its
	kebab-case name, `<my-card>` for `MyCard` and `<ui.my-card>` for
	`ui.MyCard`: it is built as `new MyCard({attributes}, [children])` and
	each attribute is checked against the component's props.

	A `<div>` or `<text>` also takes `class="p-4 bg-surface rounded-lg"`, utility
	classes over the theme's tokens resolved at compile time (see
	`ashui.style.Tw`), and `style={s}`, an `ashui.style.Style`. Classes apply
	first, then the style, then the element's own attributes.

	A value typed as a signal or computed is bound as it is. An attribute or
	text interpolation that reads a signal, by calling `.get()` or by reading
	a `@:state` field of the component it is in, becomes a computed of that
	expression, so it follows what it reads; for a component, only props typed
	`IntoReactive<T>` do. Interpolating a signal or computed reads it.
	Interpolating an element or an array of elements places them as children.
	Text and interpolations directly inside a `<div>` become a `<text>`.

	`<if {cond}>...<else>...</if>` is a `Show` and `<for {v in list}>...</for>`
	a `For`; a branch or loop body of more than one element is wrapped in a
	`<div>`. Elements take their tree from the current `Owner`.
**/
class Hxx {
	public static macro function hxx(template:Expr):Expr {
		var children = Parser.parseRoot(template, {
			defaultExtension: 'hxx',
			treatNested: nested -> single(elements(nested), nested.pos),
		});
		return single(elements(children), template.pos);
	}

	#if macro
	static var counter = 0;

	/** Loop variables in scope where the template is being lowered. **/
	static var locals:Array<{name:String, type:ComplexType}> = [];

	/** `e`'s type with the enclosing loop variables declared, or null if it does not type. **/
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

	/** The only element of a template. **/
	static function single(nodes:Array<Piece>, pos:Position):Expr {
		return switch nodes {
			case [One(e)]: e;
			case []: Context.error('hxx: the template is empty', pos);
			case [Many(e)]: Context.error('hxx: a template\'s root is one element, not an array', e.pos);
			case _: Context.error('hxx: a template has exactly one root element', pos);
		}
	}

	/** The elements of a branch or loop body, wrapped in a `Div` if there are several. **/
	static function group(nodes:Array<Piece>, pos:Position):Expr {
		return switch nodes {
			case [One(e)]: e;
			case []: Context.error('hxx: this body is empty', pos);
			case _: macro @:pos(pos) new ashui.ui.Div(null, ${childArray(nodes)});
		}
	}

	/** The children as one `Array<Element>` expression. **/
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
						append(macro $a{ones});
					ones = [];
					append(e);
			}
		if (ones.length > 0 || result == null)
			append(macro $a{ones});
		return result;
	}

	/** The children of a node as element expressions. **/
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
					var otherwise = alt == null || alt.value.length == 0 ? macro null : macro () -> ${group(elements(alt), alt.pos)};
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
							out.push(One(macro @:pos(child.pos) new ashui.ui.For(() -> $each, ($name : $valueType) -> $item)));
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

	/** An interpolation that places elements, or null for one that is text. **/
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

	/** Whether `tag` names a component class visible where the template is, other than a built-in one of ashui.ui. **/
	static function importedComponent(tag:String):Bool {
		var type = try Context.getType(className(tag)) catch (_:Dynamic) null;
		if (type == null)
			return false;
		return switch type {
			case TInst(c, _): c.get().pack.join(".") != "ashui.ui" && componentProps(type) != null;
			case _: false;
		}
	}

	/** `MyCard` as a tag: `my-card`; a package stays as it is. **/
	static function kebab(name:String):String {
		var parts = name.split('.');
		var last = ~/([a-z0-9])([A-Z])/g.replace(parts.pop(), '$1-$2');
		last = ~/([A-Z])([A-Z][a-z])/g.replace(last, '$1-$2');
		parts.push(last.toLowerCase());
		return parts.join('.');
	}

	/** The class a component tag names: `my-card` is `MyCard`, `ui.my-card` is `ui.MyCard`. **/
	static function className(tag:String):String {
		var parts = tag.split('.');
		var last = [for (word in parts.pop().split('-')) word.charAt(0).toUpperCase() + word.substr(1)].join('');
		parts.push(last);
		return parts.join('.');
	}

	/**
		`class=`'s setters: Tw's utilities, then the element's CSS classes, the
		words that are classes of the declared CSS, set on its identity.
	**/
	static function classSetters(value:Expr, el:String):Array<Expr> {
		var css = [];
		var sets = ashui.style.Tw.setters(value, macro $i{el}.node, css);
		if (css.length > 0)
			sets.unshift(macro @:pos(value.pos) ashui.css.Identity.of($i{el}.tree, $i{el}.node.id).setClasses($v{css}));
		return sets;
	}

	/** `id=`: the element's id, which CSS's `#id` selects. **/
	static function idSetter(value:Expr, el:String):Expr
		return macro @:pos(value.pos) ashui.css.Identity.of($i{el}.tree, $i{el}.node.id).setId(($value : String));

	/**
		HTML's text elements, built in: each a box of its type holding its
		text, which the user-agent stylesheet gives its look (`h1`'s size,
		`strong`'s weight, `code`'s face). Inline elements inside one sit
		beside its text in a wrapping row; text does not yet flow across them.
	**/
	static final TEXT_TAGS = ["h1", "h2", "h3", "h4", "h5", "h6", "p", "span", "strong", "b", "em", "i", "small", "code", "kbd", "mark", "s", "u", "output"];

	/** HTML's elements built in as boxes of their type, with no behaviour of their own. **/
	static final BOX_TAGS = [
		"button", "hr", "legend", "blockquote", "caption", "thead", "tbody", "tfoot", "tr", "dl", "dt", "dd", "figure", "figcaption"
	];

	/** Elements whose text and inline elements are laid out as one flow (see `ashui.text.InlineFlow`). **/
	static final FLOW_TAGS = ["p", "h1", "h2", "h3", "h4", "h5", "h6", "dt", "dd", "caption", "legend", "figcaption"];

	/** Inside a `<pre>`, whose text does not wrap. **/
	static var preformatted = 0;

	/** Built-in elements whose class is not named after their tag. **/
	static final BUILT_IN_CLASSES = ["a" => "Anchor", "textarea" => "TextArea", "ul" => "Lists.Ul", "ol" => "Lists.Ol", "colgroup" => "Table.Colgroup",
		"col" => "Table.Col", "td" => "Table.Td", "th" => "Table.Th"];

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
				case Regular(name, value) if ((name.value == 'type' && tag == 'button') || ((name.value == 'for' || name.value == 'name') && tag == 'output')):
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
		An `Image` of the bitmap in `src`. `fit`, or one of Tailwind's
		`object-cover`, `object-contain` and `object-fill` classes, says how
		it fills a box of another shape, `fill` by default as an `<img>`'s;
		other classes, `style` and attributes set the element as they do any.
	**/
	static function lowerImg(node:Node):Expr {
		var el = '__img${counter++}';
		var src:Null<Expr> = null;
		var fit:Expr = macro ashui.types.Brush.ImageFit.Fill;
		var classes = [], styles = [], own = [];
		for (a in node.attributes)
			switch a {
				case Regular(name, value) if (name.value == 'src'):
					src = value;
				case Regular(name, value) if (name.value == 'fit'):
					fit = value;
				case Regular(name, value) if (name.value == 'class'):
					var text = switch value.expr {
						case EConst(CString(s, _)): s;
						case _: Context.error("hxx: <img>'s class must be a string literal", value.pos);
					}
					var rest = [];
					for (word in ~/\s+/g.split(text))
						switch word {
							case "object-cover": fit = macro ashui.types.Brush.ImageFit.Cover;
							case "object-contain": fit = macro ashui.types.Brush.ImageFit.Contain;
							case "object-fill": fit = macro ashui.types.Brush.ImageFit.Fill;
							case _: rest.push(word);
						}
					classes = classes.concat(classSetters({expr: EConst(CString(rest.join(" "))), pos: value.pos}, el));
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
		return macro @:pos(node.name.pos) {
			var $el = new ashui.ui.Image($src, {fit: $fit});
			$b{sets};
			$i{el};
		};
	}

	/**
		An `Svg` of the markup itself, parsed and checked now. Quoted attributes
		and everything inside are SVG; on the `<svg>`, `class`, a `style` that
		is an expression, and `width`, `height` and `color` given as
		expressions set the element instead.
	**/
	static function lowerSvg(node:Node):Expr {
		var el = '__svg${counter++}';
		var classes = [], styles = [], own = [];
		var xml = Xml.createElement('svg');
		for (a in node.attributes)
			switch a {
				case Regular(name, value) if (name.value == 'class'):
					classes = classes.concat(classSetters(value, el));
				case Regular(name, {expr: EConst(CString(text))}):
					xml.set(name.value, text);
				case Regular(name, value) if (name.value == 'style'):
					styles.push(macro @:pos(value.pos) ($value : ashui.style.Style).apply($i{el}.node));
				case Regular(name, _) if (['width', 'height', 'color'].indexOf(name.value) >= 0):
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

	/** Adds the elements inside `node`, SVG all the way down, to `xml`. **/
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

	/** A `Text` from a run of text and interpolations, with its attributes. **/
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

	/** `new Tag({props}, [children])` for a `Component` subclass. **/
	static function lowerComponent(node:Node):Expr {
		var tag = node.name.value;
		// A built-in element's class is ashui.ui's, needing no import.
		var builtIn = BUILT_IN_CLASSES.exists(tag) ? BUILT_IN_CLASSES.get(tag) : className(tag);
		var type = try Context.getType(className(tag)) catch (_:Dynamic) try Context.getType("ashui.ui." + builtIn) catch (_:Dynamic)
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
						case _:
							rootSets.push(setter(el, a, '<$tag>'));
					}
				case Empty(name):
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

	/** The `Props` of `ashui.ui.Component<Props>` that `type` extends, or null. **/
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

	/** A prop's value: reactive when the prop takes `IntoReactive<T>`. **/
	static function propValue(value:Expr, propType:Type):Expr {
		return switch propType {
			case TAbstract(_.get() => {pack: ['ashui', 'layout'], name: 'IntoReactive'}, [inner]): bindable(value, inner);
			case TType(_, _) | TLazy(_): propValue(value, Context.follow(propType, true));
			case _: value;
		}
	}

	/** Handler attributes and the event each takes. **/
	static final HANDLERS = [
		"onClick" => "PointerEvent", "onPointerDown" => "PointerEvent", "onPointerUp" => "PointerEvent",
		"onPointerMove" => "PointerEvent", "onPointerEnter" => "PointerEvent", "onPointerLeave" => "PointerEvent",
		"onWheel" => "PointerEvent", "onKeyDown" => "KeyEvent", "onKeyUp" => "KeyEvent", "onTextInput" => "TextInputEvent",
		"onFocus" => "FocusEvent", "onBlur" => "FocusEvent", "onComposition" => "CompositionEvent"
	];

	/**
		`onClick={e -> ...}` and the other handlers, `focusable={true}` and
		`disabled={...}`: they go to the node's `ashui.input.Interaction`. A
		handler may take its event or nothing.
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

	/** `el.node.set(Prop.Key, value)` for one attribute, or its input setter. **/
	static function setter(el:String, attribute:Attribute, tag:String):Expr {
		return switch attribute {
			case Regular(name, value) if (inputSetter(el, name.value, value) != null):
				inputSetter(el, name.value, value);
			case Regular(name, value) if (name.value == 'notch' && tag == '<div>'):
				macro @:pos(value.pos) ashui.ui.Div.bindNotch($i{el}, $value);
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

	/** An attribute value as `Node.set` takes it: bound, computed, or constant. **/
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

	/** A condition or list read inside a `Show` or `For`: a signal or computed is read. **/
	static function read(e:Expr):Expr {
		var type = typeOf(e);
		return type != null && isReactive(type) ? macro @:pos(e.pos) $e.get() : e;
	}

	/** An interpolated value as a string piece, and whether it reads a signal. **/
	static function readValue(e:Expr):{expr:Expr, reactive:Bool} {
		var type = typeOf(e);
		if (type != null && isReactive(type))
			return {expr: macro @:pos(e.pos) $e.get(), reactive: true};
		return {expr: e, reactive: reads(e)};
	}

	/** Whether `e` reads a signal: a `.get()` call, or a `@:state` field of the component. **/
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
				case EConst(CIdent(name)) if (names.contains(name) && !shadowed.contains(name)): found = true;
				case EField({expr: EConst(CIdent('this'))}, name) if (names.contains(name)): found = true;
				case EFunction(_, _): // a nested function reads when it is called, not here
				case _: e.iter(visit);
			}
		visit(e);
		return found;
	}

	static function callsGet(e:Expr):Bool {
		var found = false;
		function visit(e:Expr)
			switch e.expr {
				case ECall({expr: EField(_, 'get')}, []): found = true;
				case EFunction(_, _): // a nested function reads when it is called, not here
				case _: e.iter(visit);
			}
		visit(e);
		return found;
	}

	static function isReactive(type:Type):Bool {
		return switch type {
			case TAbstract(_.get() => {pack: ['ashui', 'reactive'], name: 'Signal' | 'Computed'}, _): true;
			case TInst(_, _):
				Context.unify(type, (macro :ashui.reactive.ISignal<Dynamic>).toType())
				|| Context.unify(type, (macro :ashui.reactive.IComputed<Dynamic>).toType());
			case TType(_, _) | TLazy(_): isReactive(Context.follow(type, true));
			case _: false;
		}
	}
	#end
}

#if macro
/** One element, or an array of them spliced into the children. **/
private enum Piece {
	One(e:Expr);
	Many(e:Expr);
}
#end
