import ashui.core.render.Png;
import ashui.core.render.Snapshot;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Bitmap;
import ashui.types.Brush;
import ashui.ui.Hxx.hxx;

/**
	Bitmaps: a 240 × 120 picture, painted in pixels here and encoded as a
	PNG, decoded as a `Bitmap` and drawn by `<img>` stretched, letterboxed
	with `object-contain`, cropped with `object-cover`, cropped to a round
	avatar with `rounded-full`, and as the background of a card with text
	over it. Rendered at one and two image pixels per layout unit.
**/
class Bitmaps {
	static function main() {
		ThemeState.init(DefaultTheme.bundle(), Light);
		var page = ThemeState.get().color(Background);
		var picture = Bitmap.fromBytes(Png.encode(240, 120, paint(240, 120)));
		var build = () -> hxx('
			<div class="flex flex-row flex-wrap items-start p-6 gap-6" width={640} height={300}>
				<div class="flex flex-col items-center gap-2">
					<img src={picture} class="w-24 h-24 rounded-lg" />
					<text class="text-xs text-text-secondary">fill</text>
				</div>
				<div class="flex flex-col items-center gap-2">
					<img src={picture} class="w-24 h-24 rounded-lg bg-surface-elevated object-contain" />
					<text class="text-xs text-text-secondary">object-contain</text>
				</div>
				<div class="flex flex-col items-center gap-2">
					<img src={picture} class="w-24 h-24 rounded-lg object-cover" />
					<text class="text-xs text-text-secondary">object-cover</text>
				</div>
				<div class="flex flex-col items-center gap-2">
					<img src={picture} class="w-24 h-24 rounded-full object-cover border-4 border-surface shadow-md" />
					<text class="text-xs text-text-secondary">rounded-full</text>
				</div>
				<div class="flex flex-col justify-end p-4 rounded-xl shadow-lg" width={240} height={120} bg={Brush.bitmap(picture, Cover)}>
					<text class="text-lg font-bold text-text-inverse">A card</text>
					<text class="text-xs text-text-inverse">on a bitmap background</text>
				</div>
			</div>
		');
		Snapshot.scene("bitmaps", 640, 300, build, page.rgb(), page.a);
		Snapshot.scene("bitmaps@2x", 640, 300, build, page.rgb(), page.a, 2.0);
	}

	/** A sunset of sorts: a sky graded top to bottom, a sun, and hills, straight RGBA. **/
	static function paint(w:Int, h:Int):haxe.io.Bytes {
		var out = haxe.io.Bytes.alloc(w * h * 4);
		for (y in 0...h)
			for (x in 0...w) {
				var t = y / h;
				var r = 255 * (0.35 + 0.65 * t), g = 120 + 80 * t, b = 220 - 160 * t;
				var dx = x - w * 0.7, dy = y - h * 0.55;
				if (dx * dx + dy * dy < 22 * 22) {
					r = 255;
					g = 220;
					b = 90;
				}
				var hill = h * (0.7 + 0.08 * Math.sin(x / w * 7.0));
				if (y > hill) {
					r = 40 + 30 * Math.sin(x / 9.0);
					g = 110;
					b = 70;
				}
				var i = (y * w + x) * 4;
				out.set(i, Std.int(r));
				out.set(i + 1, Std.int(g));
				out.set(i + 2, Std.int(b));
				out.set(i + 3, 255);
			}
		return out;
	}
}
