import ashui.layout.DisplayList;
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.theme.ThemeState;
import ashui.ui.Div;
import ashui.ui.Hxx.hxx;

class TwBorders {
	static function check(ok:Bool,message:String):Void { if (!ok) throw message; }
	static function main():Void {
		ThemeState.init(ashui.theme.themes.DefaultTheme.bundle(),Light);
		var tree=new LayoutTree(), list=new DisplayList();
		var bare:Div=Owner.root(tree,_ -> hxx('<div class="w-16 h-16 bg-white border"/>'));
		var left:Div=Owner.root(tree,_ -> hxx('<div class="w-16 h-16 bg-white border-l"/>'));
		var both:Div=Owner.root(tree,_ -> hxx('<div class="w-16 h-16 bg-white border border-l"/>'));
		var styled=Owner.root(tree,_ -> new Div({style:ashui.style.Tw.tw("w-16 h-16 bg-white border-l")}));
		var hover:Div=Owner.root(tree,_ -> hxx('<div class="w-16 h-16 bg-white border-0 hover:border"/>'));
		var explicit:Div=Owner.root(tree,_ -> hxx('<div class="w-16 h-16 bg-white border border-primary"/>'));
		var attribute:Div=Owner.root(tree,_ -> hxx('<div class="w-16 h-16 bg-white border" borderColor={new ashui.types.Color(0xff0000)}/>'));
		function sample(box:Div):Array<Float> {
			tree.flush(); tree.computeLayout(box.node,64,64); list.update(tree,box.node);
			check(list.count>0,"Missing border/background record");
			return [for (i in 64...80) list.get(0,i)];
		}
		function color(values:Array<Float>,rgb:Int,alpha:Float=1):Bool return Math.abs(values[0]-(rgb>>16&255)/255)<.01 && Math.abs(values[1]-(rgb>>8&255)/255)<.01 && Math.abs(values[2]-(rgb&255)/255)<.01 && Math.abs(values[3]-alpha)<.01;
		var theme=ThemeState.get().color(Border).rgb();
		var initial=sample(bare);
		check(color(initial,theme,ThemeState.get().color(Border).a),'border is invisible or ignores theme color: $initial');
		sample(left); check([for(i in 16...20) Std.int(list.get(0,i))].join(",")=="0,0,0,1","border-l painted other edges");
		check(color(sample(left).slice(12,16),theme,ThemeState.get().color(Border).a),"border-l has no color");
		check(color(sample(styled).slice(12,16),theme,ThemeState.get().color(Border).a),"Tw.tw style has no default border color");
		ashui.input.Interaction.of(hover.node).hovered.set(true);
		check(color(sample(hover),theme,ThemeState.get().color(Border).a) && list.get(0,16)==1,"Variant border width lost the fallback");
		sample(both); check([for(i in 16...20) Std.int(list.get(0,i))].join(",")=="1,1,1,1","border border-l lost an edge");
		check(color(sample(explicit),ThemeState.get().color(Primary).rgb(),ThemeState.get().color(Primary).a),"Default replaced border-primary");
		check(color(sample(attribute),0xff0000),"Default replaced explicit borderColor");
		ThemeState.get().setScheme(Dark);
		check(color(sample(bare),ThemeState.get().color(Border).rgb(),ThemeState.get().color(Border).a),"Default border did not follow the theme");
		var sheet=ashui.css.Css.load("div { border-color: #123456; }");
		check(color(sample(bare),0x123456),"Default overrode authored CSS");
		ashui.css.Css.remove(sheet);
		check(color(sample(bare),ThemeState.get().color(Border).rgb(),ThemeState.get().color(Border).a),"Removing CSS did not restore the default");
		#if ashui_border_pixels
		ThemeState.get().setColorOverride(Border,ashui.theme.Rgba.fromHex(0xff0000));
		var renderer=ashui.core.render.Offscreen.create(); renderer.clear=0xffffff; renderer.clearAlpha=1;
		function pixel(box:Div,x:Int,y:Int):Int {
			tree.flush(); tree.computeLayout(box.node,64,64);
			var bytes=renderer.renderToRgba8(box,64,64), at=(y*64+x)*4;
			return bytes.get(at)<<16|bytes.get(at+1)<<8|bytes.get(at+2);
		}
		check(pixel(bare,0,32)==0xff0000 && pixel(bare,63,32)==0xff0000 && pixel(bare,32,0)==0xff0000 && pixel(bare,32,63)==0xff0000,"border did not paint four edges");
		check(pixel(left,0,32)==0xff0000 && pixel(left,63,32)==0xffffff && pixel(left,32,0)==0xffffff,"border-l did not paint only its left edge");
		check(pixel(both,63,32)==0xff0000,"border border-l lost its right edge");
		#end
		Sys.println("Tw borders: visible defaults, side widths, explicit colors, authored CSS and theme changes passed");
	}
}
