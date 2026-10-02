package ashui.render;

#if macro
#if ashui_caribou
import caribou.hxsl.Ast.TVar;
import caribou.hxsl.Extension;
import caribou.hxsl.Extensions;
#else
import hlwgpu.hxsl.Ast.TVar;
import hlwgpu.hxsl.Extension;
import hlwgpu.hxsl.Extensions;
#end

/**
	ashui's extension of HXSL for `UiShader`s. Each draws one display-list
	record per instance, so each gets the record as the `primitive` input,
	field for field as `ashui.layout.DisplayList` packs it. Globals go in a
	`frame` block, bound once per frame and shared by every UI shader.

	Registered from ashui's extraParams.hxml, or `--macro
	ashui.render.UiFramework.register()`.
**/
class UiFramework extends Extension {
	public static function register() {
		Extensions.register(new UiFramework(), "ashui.render.UiShader");
	}

	override function prelude():Null<haxe.macro.Expr> {
		return macro {
			@input var primitive : {
				bounds : Vec4,
				cornerRadius : Vec4,
				color : Vec4,
				color2 : Vec4,
				border : Vec4,
				borderColor : Vec4,
				shadow : Vec4,
				shadowColor : Vec4,
				clipBounds : Vec4,
				clipRadius : Vec4,
				gradient : Vec4,
				typeInfo : Vec4
			};
			@global var viewport : Vec2;
		};
	}

	override function block(v:TVar, path:String):Null<String> {
		return v.kind == Global ? "frame" : null;
	}
}
#end
