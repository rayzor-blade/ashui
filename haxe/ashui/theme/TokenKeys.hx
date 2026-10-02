package ashui.theme;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;

/**
	Builds a token key enum: `enum abstract XToken(String)` whose values name
	the fields of one `Tokens` record. Checks that every value names a field
	and every field has a value, then adds `of(record)` reading that field.
**/
class TokenKeys {
	public static function build(record:String, value:String):Array<Field> {
		var fields = Context.getBuildFields();
		var pos = Context.currentPos();
		var recordFields = switch Context.follow(Context.getType(record)) {
			case TAnonymous(a): [for (f in a.get().fields) f.name];
			case _: Context.error('$record is not a record', pos);
		}
		var cases:Array<Case> = [];
		var named = new Map<String, Bool>();
		for (f in fields)
			switch f.kind {
				case FVar(_, {expr: EConst(CString(name))}):
					if (recordFields.indexOf(name) < 0)
						Context.error('${f.name} names "$name", which $record has no field for', f.pos);
					named.set(name, true);
					cases.push({values: [macro $v{name}], expr: macro set.$name});
				case _:
			}
		for (name in recordFields)
			if (!named.exists(name))
				Context.error('$record.$name has no key here', pos);
		var recordType = Context.toComplexType(Context.getType(record));
		var valueType = switch Context.parse('(null : $value)', pos) {
			case {expr: EParenthesis({expr: ECheckType(_, t)})} | {expr: ECheckType(_, t)}: t;
			case _: Context.error('$value is not a type', pos);
		}
		var body:Expr = {expr: ESwitch(macro this, cases, macro throw 'no token ' + this), pos: pos};
		fields.push({
			name: "of",
			doc: 'This token\'s value in `set`.',
			access: [APublic],
			kind: FFun({args: [{name: "set", type: recordType}], ret: valueType, expr: macro return $body}),
			pos: pos
		});
		return fields;
	}
}
#end
