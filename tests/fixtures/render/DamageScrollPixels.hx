import ashui.core.render.Offscreen;
import ashui.css.Css;
import ashui.draw.DrawContext;
import ashui.layout.Element;
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.types.Brush;
import ashui.types.Color;
import ashui.ui.Div;
import ashui.ui.Ref;
import gpu.GpuTextureViewDescriptor;

/**
	Scrolled content, icons, text and canvases under a glass panel, drawn as the parts of the last frame that changed and drawn
	whole, which must give the same pixels: a list scrolled to several offsets, an icon's tint, a label, a bar in a row,
	and a row added. What each frame draws, whole, in parts or not at all, is printed.
**/
class DamageScrollPixels {
	static var checks = 0;

	static function check(what:String, ok:Bool, ?detail:Dynamic):Void {
		if (!ok)
			throw what + (detail == null ? "" : ' ($detail)');
		checks++;
		Sys.println('ok   $what');
	}

	static function main():Void {
		ashui.theme.ThemeState.init(ashui.theme.themes.DefaultTheme.bundle(), Light);
		var sheet = Css.load('
			#list { position: absolute; left: 0px; top: 0px; width: 150px; height: 200px; overflow-y: auto; display: flex; flex-direction: column; }
			#glass { position: absolute; left: 120px; top: 20px; width: 150px; height: 100px; border-radius: 12px;
				background: rgba(255, 255, 255, 0.35); backdrop-filter: blur(6px); }
			#chip { position: absolute; left: 400px; top: 230px; width: 60px; height: 40px; border-radius: 6px; background: #0ea5e9; }
		');
		var docA = ashui.svg.SvgDocument.parse('<svg viewBox="0 0 24 24"><path fill="currentColor" d="M8 5v14l11-7z"/></svg>');
		var docB = ashui.svg.SvgDocument.parse('<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="8" fill="none" stroke="currentColor" stroke-width="3"/></svg>');
		var docC = ashui.svg.SvgDocument.parse('<svg viewBox="0 0 24 24"><rect x="3" y="3" width="18" height="18" rx="4" fill="#16a34a"/></svg>');
		var rowCount = Signal.make(24);
		var tones = [for (i in 0...40) Signal.make(new Color(i % 3 == 0 ? 0x2563eb : 0xdc2626))];
		var labels = [for (i in 0...40) Signal.make('Row $i')];
		var level = Signal.make(0.3);
		var bar = (ctx:DrawContext) -> {
			ctx.fillRect(0, 0, ctx.width, ctx.height, Brush.solid(0x111827, 0.25));
			ctx.fillRect(0, 0, ctx.width * level.get(), ctx.height, Brush.solid(0xfacc15));
		};
		var tree = new LayoutTree(), dispose = () -> {};
		var listRef = new Ref<Div>();
		function row(i:Int):Element {
			var icon = new ashui.ui.Svg(i % 5 == 4 ? docC : i % 2 == 0 ? docA : docB, {width: 20, height: 20, color: tones[i]});
			return <div class="flex flex-row items-center gap-2 h-9 shrink-0 px-2">{icon}<text class="text-sm text-primary">${labels[i].get()}</text>
				<if {i % 8 == 2}><canvas width={60} height={8} draw={bar} /></if></div>;
		}
		var root = Owner.root(tree, stop -> {
			dispose = stop;
			return <div width={480} height={300} class="bg-background">
				<div id="list" ref={listRef}><for {i in [for (k in 0...rowCount.get()) k]}>{row(i)}</for></div>
				<div id="glass" />
				<div id="chip" />
			</div>;
		});
		var damaged = Offscreen.create(), whole = new Offscreen(damaged.device, damaged.format);
		damaged.clearAlpha = whole.clearAlpha = 1.0;
		damaged.clear = whole.clear = 0xffffff;
		whole.damage = false;
		whole.diffUpload = false;
		function scroll(y:Float) {
			// Not a scroll container until the first layout.
			var scrolling = ashui.input.Scroll.of(listRef.get().node);
			if (scrolling != null)
				scrolling.scrollTo(0, y);
		}
		var seen = new Map<String, Int>();
		for (scale in [1, 2]) {
			damaged.scale = whole.scale = scale;
			var width = 480 * scale, height = 300 * scale;
			var a = damaged.createTexture(width, height), b = damaged.createTexture(width, height);
			var viewA = a.createView(new GpuTextureViewDescriptor()), viewB = b.createView(new GpuTextureViewDescriptor());
			level.set(0.3);
			rowCount.set(24);
			for (i in 0...40) {
				tones[i].set(new Color(i % 3 == 0 ? 0x2563eb : 0xdc2626));
				labels[i].set('Row $i');
			}
			scroll(0);
			var steps:Array<{name:String, change:Void->Void}> = [
				{name: "the first frame", change: () -> {}},
				{name: "nothing changed", change: () -> {}},
				{name: "the list scrolled a row", change: () -> scroll(36)},
				{name: "the list scrolled further", change: () -> scroll(120)},
				{name: "the list scrolled a pixel", change: () -> scroll(121)},
				{name: "the list scrolled back", change: () -> scroll(0)},
				{name: "an icon's tint", change: () -> tones[3].set(new Color(0x9333ea))},
				{name: "a label", change: () -> labels[5].set("Row five, longer")},
				{name: "a bar in a row", change: () -> level.set(0.8)},
				{name: "scrolled while a bar changes", change: () -> {
					scroll(60);
					level.set(0.5);
				}},
				{name: "an icon under the glass, tinted", change: () -> tones[2].set(new Color(0x0d9488))},
				{name: "nothing changed again", change: () -> {}},
				{name: "a row added", change: () -> rowCount.set(25)},
				{name: "the list scrolled after that", change: () -> scroll(200)},
				{name: "the list scrolled to its end", change: () -> scroll(10000)}
			];
			for (s in steps) {
				s.change();
				damaged.render(root, viewA, 480, 300);
				whole.render(root, viewB, 480, 300);
				var pa = damaged.readRgba8(a, width, height), pb = damaged.readRgba8(b, width, height);
				var worst = 0, differing = 0;
				for (i in 0...pa.length) {
					var d = Std.int(Math.abs(pa.get(i) - pb.get(i)));
					if (d > 0)
						differing++;
					if (d > worst)
						worst = d;
				}
				var drew = damaged.drew;
				var how = drew == "full" || drew == "none" ? drew : "part";
				seen.set(how, (seen.exists(how) ? seen.get(how) : 0) + 1);
				check('${scale}x: ${s.name} is drawn ${drew} and as the whole frame is', worst <= 1, 'worst difference $worst in $differing bytes');
			}
			viewA.destroy();
			viewB.destroy();
			a.destroy();
			b.destroy();
		}
		Sys.println('kinds: $seen');
		Css.remove(sheet);
		dispose();
		tree.dispose();
		Sys.println('$checks checks: ALL PASSED');
	}
}
