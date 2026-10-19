import ashui.core.render.Offscreen;
import ashui.css.Css;
import ashui.draw.DrawContext;
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.types.Brush;
import ashui.types.Style;
import gpu.GpuTextureViewDescriptor;

/**
	A frame drawn as the part of the last that changed is the frame drawn whole. Two renderers on one device draw the same
	tree each step, one allowed to draw in parts and one not, and their pixels are compared: a glass panel blurring stripes, over
	which a canvas and a number change, a box that changes colour, shadows, and steps where nothing changes or the tree does.
**/
class DamagePixels {
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
			#glass { position: absolute; left: 24px; top: 24px; width: 170px; height: 120px; border-radius: 14px; padding: 10px;
				background: rgba(255, 255, 255, 0.35); backdrop-filter: blur(6px); box-shadow: 0 6px 14px rgba(0, 0, 0, 0.35); }
			#solid { position: absolute; left: 24px; top: 170px; width: 100px; height: 46px; border-radius: 8px; background: #2563eb;
				box-shadow: 0 3px 8px rgba(0, 0, 0, 0.4); }
			#chip { position: absolute; left: 254px; top: 30px; width: 54px; height: 40px; border-radius: 6px; }
			#extra { position: absolute; left: 210px; top: 120px; width: 50px; height: 30px; background: #16a34a; }
			#number { color: #111827; font-size: 16px; font-weight: 700; }
		');
		var level = Signal.make(0.2), count = Signal.make(0), warm = Signal.make(false), extra = Signal.make(false);
		var tree = new LayoutTree(), dispose = () -> {};
		var stripes = (ctx:DrawContext) -> {
			for (i in 0...16)
				ctx.fillRect(i * 20, 0, 10, 240, Brush.solid(i % 2 == 0 ? 0xdc2626 : 0x1d4ed8));
		};
		var bar = (ctx:DrawContext) -> {
			ctx.fillRect(0, 0, ctx.width, ctx.height, Brush.solid(0x111827, 0.25));
			ctx.fillRect(0, 0, ctx.width * level.get(), ctx.height, Brush.solid(0xfacc15));
		};
		var root = Owner.root(tree, stop -> {
			dispose = stop;
			return <div width={320} height={240} class="bg-background">
				<canvas position={Absolute} left={0} top={0} width={320} height={240} draw={stripes} />
				<div id="glass" class="flex-col gap-2">
					<text id="number">${Std.string(count.get())}</text>
					<canvas width={150} height={24} draw={bar} />
				</div>
				<div id="solid" />
				<div id="chip" bg={warm.get() ? Brush.solid(0xf97316) : Brush.solid(0x0ea5e9)} />
				<if {extra.get()}><div id="extra" /></if>
			</div>;
		});
		var damaged = Offscreen.create(), whole = new Offscreen(damaged.device, damaged.format);
		damaged.clearAlpha = whole.clearAlpha = 1.0;
		damaged.clear = whole.clear = 0xffffff;
		whole.damage = false;
		whole.diffUpload = false;
		var seen = new Map<String, Int>();
		for (scale in [1, 2]) {
			damaged.scale = whole.scale = scale;
			level.set(0.2);
			count.set(0);
			warm.set(false);
			extra.set(false);
			var width = 320 * scale, height = 240 * scale;
			var a = damaged.createTexture(width, height), b = damaged.createTexture(width, height);
			var viewA = a.createView(new GpuTextureViewDescriptor()), viewB = b.createView(new GpuTextureViewDescriptor());
			// Each step: what changes, and what the damaged renderer should say it drew.
			var steps:Array<{name:String, change:Void->Void, expect:String}> = [
				{name: "the first frame", change: () -> {}, expect: "full"},
				{name: "nothing changed", change: () -> {}, expect: "none"},
				{name: "the canvas under glass", change: () -> level.set(0.7), expect: "part"},
				{name: "the number in the glass", change: () -> count.set(count.get() + 1), expect: "part"},
				{name: "the colour of a box away from the glass", change: () -> warm.set(true), expect: "part"},
				{name: "the canvas again", change: () -> level.set(0.4), expect: "part"},
				{name: "the canvas and the colour together", change: () -> {
					level.set(0.9);
					warm.set(false);
				}, expect: "part"},
				{name: "nothing changed again", change: () -> {}, expect: "none"},
				{name: "a box added, so the records differ in number", change: () -> extra.set(true), expect: "full"},
				{name: "the canvas after that", change: () -> level.set(0.1), expect: "part"},
				{name: "the box removed", change: () -> extra.set(false), expect: "full"},
				{name: "the number once more", change: () -> count.set(count.get() + 7), expect: "part"}
			];
			var step = 0;
			for (s in steps) {
				s.change();
				step++;
				damaged.render(root, viewA, 320, 240);
				whole.render(root, viewB, 320, 240);
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
				check('${scale}x: ${s.name} is drawn $how and as the whole frame is', how == s.expect && worst <= 1, 'drew $drew, worst difference $worst in $differing bytes');
			}
			viewA.destroy();
			viewB.destroy();
			a.destroy();
			b.destroy();
		}
		check("some frames were drawn in parts, some not at all, and some whole", seen.exists("part") && seen.exists("none") && seen.exists("full"), seen);
		Css.remove(sheet);
		dispose();
		tree.dispose();
		Sys.println('$checks checks: ALL PASSED');
	}
}
