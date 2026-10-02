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

	    hxx('<Div width={w} bg={color}><Text>Value: ${count}</Text></Div>')

	`Div` and `Text` become their constructor plus one `node.set(Prop.X, v)`
	per attribute, with no attribute object; `bg` is `Prop.Background` and any
	other name is the key of that name, capitalised. Any other tag is a
	component, built as `new Tag({attributes}, [children])`.

	A value typed as a signal or computed is bound as it is. An attribute or
	text interpolation that calls `.get()` becomes a computed of that
	expression, so it follows what it reads. Interpolating a signal or
	computed reads it. Text and interpolations directly inside a `Div` become
	a `Text`. Elements take their tree from the current `Owner`.
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

	static function single(nodes:Array<Expr>, pos:Position):Expr {
		return switch nodes {
			case [one]: one;
			case []: Context.error('hxx: the template is empty', pos);
			case _: Context.error('hxx: a template has exactly one root element', pos);
		}
	}

	/** The children of a node as element expressions. **/
	static function elements(children:Children):Array<Expr> {
		var out = [];
		if (children == null)
			return out;
		var run:Array<Child> = [];
		function endText() {
			if (run.length > 0)
				out.push(textElement(run, [], run[0].pos));
			run = [];
		}
		for (child in children.value)
			switch child.value {
				case CNode(node):
					endText();
					out.push(lowerNode(node));
				case CText(text):
					run.push(child);
				case CExpr(e) if (isElement(e)):
					endText();
					out.push(e);
				case CExpr(_):
					run.push(child);
				case CSplat(e):
					Context.error('hxx: spreading children is not supported', e.pos);
				case _:
					Context.error('hxx: control flow is not supported yet', child.pos);
			}
		endText();
		return out;
	}

	static function lowerNode(node:Node):Expr {
		return switch node.name.value {
			case 'Div': lowerDiv(node);
			case 'Text': textElement(node.children == null ? [] : node.children.value, node.attributes, node.name.pos);
			case 'if' | 'else' | 'for' | 'switch' | 'case' | 'let':
				Context.error('hxx: control flow is not supported yet', node.name.pos);
			case _: lowerComponent(node);
		}
	}

	static function lowerDiv(node:Node):Expr {
		var el = '__div${counter++}';
		var kids = elements(node.children);
		var sets = [for (a in node.attributes) setter(el, a, 'Div')];
		return macro @:pos(node.name.pos) {
			var $el = new ashui.ui.Div(null, $a{kids});
			$b{sets};
			$i{el};
		};
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
		var sets = [];
		for (a in attributes)
			switch a {
				case Regular(name, value) if (name.value == 'wrap'):
					options.push({field: 'wrap', expr: value});
				case _:
					sets.push(setter(el, a, 'Text'));
			}
		var attr = options.length == 0 ? macro null : {expr: EObjectDecl(options), pos: pos};
		return macro @:pos(pos) {
			var $el = new ashui.ui.Text($content, $attr);
			$b{sets};
			$i{el};
		};
	}

	static function lowerComponent(node:Node):Expr {
		var parts = node.name.value.split('.');
		var path:TypePath = {pack: parts.slice(0, -1), name: parts[parts.length - 1]};
		var fields = [
			for (a in node.attributes)
				switch a {
					case Regular(name, value): {field: name.value, expr: value};
					case Empty(name): {field: name.value, expr: macro @:pos(name.pos) true};
					case Splat(e): Context.error('hxx: spreading attributes is not supported', e.pos);
				}
		];
		var args:Array<Expr> = [];
		var kids = elements(node.children);
		if (fields.length > 0 || kids.length > 0)
			args.push(fields.length > 0 ? {expr: EObjectDecl(fields), pos: node.name.pos} : macro null);
		if (kids.length > 0)
			args.push(macro $a{kids});
		return {expr: ENew(path, args), pos: node.name.pos};
	}

	/** `el.node.set(Prop.Key, value)` for one attribute. **/
	static function setter(el:String, attribute:Attribute, tag:String):Expr {
		return switch attribute {
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
		var type = try Context.typeof(value) catch (_:Dynamic) null;
		if (type != null && isReactive(type))
			return value;
		if (callsGet(value)) {
			var ct = valueType.toComplexType();
			return macro @:pos(value.pos) ashui.reactive.Computed.make(() -> ($value : $ct));
		}
		return value;
	}

	/** An interpolated value as a string piece, and whether it reads a signal. **/
	static function readValue(e:Expr):{expr:Expr, reactive:Bool} {
		var type = try Context.typeof(e) catch (_:Dynamic) null;
		if (type != null && isReactive(type))
			return {expr: macro @:pos(e.pos) $e.get(), reactive: true};
		return {expr: e, reactive: callsGet(e)};
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

	static function isElement(e:Expr):Bool {
		var type = try Context.typeof(e) catch (_:Dynamic) null;
		return type != null && Context.unify(type, Context.getType('ashui.layout.Element'));
	}
	#end
}
