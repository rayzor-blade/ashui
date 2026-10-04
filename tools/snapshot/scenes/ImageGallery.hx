import ashui.core.render.Snapshot;
import ashui.draw.Affine;
import ashui.draw.DrawContext;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Bitmap;
import ashui.types.Brush;
import ashui.types.Style;

/**
	Photos, from Blinc's examples (`tools/snapshot/assets`): an album cover,
	a landscape and an illustration in WebP, an avatar in JPEG. Each drawn
	by `<img>` in its three fits into one wide box (cover crops, contain
	letterboxes, fill stretches), rounded and as a circle, the largest from
	the full 2048-pixel original in Blinc's checkout when it is there; as a box's
	background; then on a canvas, turned, scaled and faded. Writes
	`.ashui/snapshots/images.png` (`images-light` with `SCHEME=light`).
**/
class ImageGallery {
	static function main() {
		var light = Sys.getEnv("SCHEME") == "light";
		ThemeState.init(DefaultTheme.bundle(), light ? Light : Dark);
		var page = ThemeState.get().color(Background);
		var album = Bitmap.embed("assets/album.webp"), plains = Bitmap.embed("assets/plains.webp");
		var planet = Bitmap.embed("assets/planet.webp"), avatar = Bitmap.embed("assets/avatar.jpg");
		// The avatar at its full 2048 by 2048, from Blinc's checkout when it is there: a large photo, resampled to the 96 it is drawn at.
		var original = "../../../blinc/examples/blinc_app_examples/examples/assets/avatar.jpg";
		var full = sys.FileSystem.exists(original) ? Bitmap.load(original) : avatar;
		function canvas(ctx:DrawContext) {
			ctx.image(planet, 0, 0, 240, 180);
			ctx.pushTransform(Affine.translation(370, 90).after(Affine.rotation(-0.2)));
			ctx.image(album, -100, -67, 200, 134);
			ctx.popTransform();
			ctx.pushOpacity(0.5);
			ctx.image(plains, 500, 20, 140, 140);
			ctx.popOpacity();
		}
		var build = () -> <div flexDirection={Column} padding={32} gap={28} width={760}>
			<div flexDirection={Row} gap={20}>
				<div flexDirection={Column} gap={8}>
					<img src={planet} class="object-cover rounded-xl" width={220} height={140} />
					<text class="text-xs text-text-secondary">cover: cropped to fill</text>
				</div>
				<div flexDirection={Column} gap={8}>
					<img src={planet} class="object-contain rounded-xl" width={220} height={140} bg={Brush.solid(0x000000, 0.25)} />
					<text class="text-xs text-text-secondary">contain: whole, letterboxed</text>
				</div>
				<div flexDirection={Column} gap={8}>
					<img src={planet} class="object-fill rounded-xl" width={220} height={140} />
					<text class="text-xs text-text-secondary">fill: stretched</text>
				</div>
			</div>
			<div flexDirection={Row} gap={20} alignItems={Center}>
				<img src={full} class="object-cover rounded-full" width={96} height={96} />
				<img src={avatar} class="object-cover rounded-full" width={56} height={56} />
				<img src={avatar} class="object-cover rounded-full" width={32} height={32} />
				<img src={album} class="object-cover rounded-2xl" width={180} height={120} />
				<div class="rounded-2xl" width={200} height={120} bg={Brush.bitmap(plains, Cover)} flexDirection={Column} justifyContent={Justify.End} padding={12}>
					<text class="text-sm font-semibold text-white">As a background</text>
				</div>
			</div>
			<canvas width={680} height={190} draw={canvas} />
		</div>;
		Snapshot.scene(light ? "images-light" : "images", 760, 640, build, page.rgb(), page.a, 2.0, 1.0);
	}
}
