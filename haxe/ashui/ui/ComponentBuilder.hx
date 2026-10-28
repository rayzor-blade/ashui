package ashui.ui;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;

/**
	Generates reactive state accessors and template bodies for component subclasses.

	`@:state var x:T = init` becomes a signal-backed property. Reads participate
	in dependency tracking; assignments update the signal. Hot reload transfers
	these signals to replacement instances. With `-D ashui_hot_reload`, a new
	state field initializes on first access in an existing instance.

	Also supports the template-body shorthand `function render() '<template>'`
	by expanding it to a return from the underlying HXX macro.
**/
class ComponentBuilder {
	public static function build():Array<Field> {
		var out:Array<Field> = [];
		var signals:Array<String> = [];
		for (field in Context.getBuildFields()) {
			if (field.meta != null && Lambda.exists(field.meta, m -> m.name == ':state')) {
				for (f in stateField(field))
					out.push(f);
				signals.push('${field.name}__state');
				continue;
			}
			if (field.name == 'render')
				templateBody(field);
			out.push(field);
		}
		if (signals.length > 0)
			out.push(takeState(signals));
		return out;
	}

	/** Generates `__takeState(old)` to transfer superclass signals, then this class's state signals. **/
	static function takeState(signals:Array<String>):Field {
		var self = Context.toComplexType(Context.getLocalType());
		var pos = Context.currentPos();
		// An old instance built before a reload added a state field has none of it: this one keeps its own.
		var copies = [for (s in signals) macro if (from.$s != null) $i{s} = from.$s];
		return {
			name: '__takeState',
			pos: pos,
			access: [APrivate, AOverride],
			meta: [{name: ':noCompletion', pos: pos}],
			kind: FFun({
				args: [{name: 'old', type: macro :ashui.ui.Component<Dynamic>}],
				ret: macro :Void,
				expr: macro {
					super.__takeState(old);
					var from:$self = cast old;
					$b{copies};
				},
			}),
		};
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
				// Under hot reload, an instance built before a reload added this field reads it as null,
				// so the getter and setter make it from the initial value on first use.
				var read = Context.defined("ashui_hot_reload") ? macro {
					if ($i{signal} == null)
						$i{signal} = ashui.reactive.Signal.make(($init : $type));
					$i{signal};
				} : macro $i{signal};
					[
						{
							name: signal,
							pos: pos,
							access: [APrivate],
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
							kind: FFun({args: [], ret: type, expr: macro return $read.get()}),
						},
						{
							name: 'set_${field.name}',
							pos: pos,
							access: [APrivate, AInline],
							kind: FFun({
								args: [{name: 'value', type: type}],
								ret: type,
								expr: macro {
									$read.set(value);
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
						if (fn.ret == null) fn.ret = macro :ashui.layout.Element;
					case _:
				}
			case _:
		}
	}
}
#end
