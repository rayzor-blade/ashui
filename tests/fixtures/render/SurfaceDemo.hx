import ashui.ui.Surface;
import ashui.types.PixelSurface;
import ashui.types.ObjectFit;

class SurfaceDemo {
	static function main() {
		var s = new PixelSurface(8, 4);
		var e:ashui.layout.Element = <surface source={s} fit={ObjectFit.Cover} />;
		trace("compiled", e != null);
	}
}
