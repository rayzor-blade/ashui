package ashui.ui;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;

/**
	Runs on every `Component` subclass:

	- `@:state var x:T = init` becomes a property backed by a signal: reading
	  `x` reads the signal, so a computed, watch or template attribute that
	  reads it follows it, and assigning `x` sets the signal.
	- `function render() '<template>'` becomes `return hxx('<template>')`.
**/
class ComponentBuilder {
	public static function build():Array<Field> {
		var out:Array<Field> = [];
		for (field in Context.getBuildFields()) {
			if (field.meta != null && Lambda.exists(field.meta, m -> m.name == ':state')) {
				for (f in stateField(field))
					out.push(f);
				continue;
			}
			if (field.name == 'render')
				templateBody(field);
			out.push(field);
		}
		return out;
	}

	static function stateField(field:Field):Array<Field> {
		var pos = field.pos;
		return switch field.kind {
			case FVar(type, init):
				if (type == null)
					Context.error('@:state ${field.name} needs a type', pos);
				if (init == null)
					Context.error('@:state ${field.name} needs an initial value', pos);
				var signal = '${field.name}__state';
				[
					{
						name: signal,
						pos: pos,
						access: [APrivate, AFinal],
						kind: FVar(macro :ashui.reactive.Signal<$type>, macro ashui.reactive.Signal.make(($init : $type))),
					},
					{
						name: field.name,
						pos: pos,
						access: field.access,
						meta: field.meta,
						doc: field.doc,
						kind: FProp('get', 'set', type),
					},
					{
						name: 'get_${field.name}',
						pos: pos,
						access: [APrivate, AInline],
						kind: FFun({args: [], ret: type, expr: macro return $i{signal}.get()}),
					},
					{
						name: 'set_${field.name}',
						pos: pos,
						access: [APrivate, AInline],
						kind: FFun({
							args: [{name: 'value', type: type}],
							ret: type,
							expr: macro {
								$i{signal}.set(value);
								return value;
							},
						}),
					},
				];
			case _:
				Context.error('@:state goes on a var', pos);
		}
	}

	static function templateBody(field:Field):Void {
		switch field.kind {
			case FFun(fn) if (fn.expr != null):
				switch fn.expr.expr {
					case EConst(CString(_)):
						var template = fn.expr;
						fn.expr = macro @:pos(template.pos) return ashui.ui.Hxx.hxx($template);
						if (fn.ret == null)
							fn.ret = macro :ashui.layout.Element;
					case _:
				}
			case _:
		}
	}
}
#end
