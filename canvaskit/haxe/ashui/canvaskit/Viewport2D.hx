package ashui.canvaskit;

import ashui.draw.Affine;
import ashui.reactive.Signal;

/**
	Where a 2D canvas looks: how far its content is panned and how far it
	is zoomed. A point of the content at `(x, y)` is drawn on screen at
	`zoom * (x + panX)`, `zoom * (y + panY)`, so pan is in content units.

	`panX`, `panY` and `zoom` are signals: a canvas that draws through the
	viewport draws again when it moves, and only then.

	```haxe
	var view = new Viewport2D();
	view.zoomAt(320, 200, 1.25); // nearer, keeping the point under the cursor still
	var p = view.screenToContent(pointerX, pointerY);
	```
**/
class Viewport2D {
	public final panX = Signal.make(0.0);
	public final panY = Signal.make(0.0);
	public final zoom = Signal.make(1.0);

	/** The nearest and furthest it zooms. **/
	public var minZoom = 0.1;

	public var maxZoom = 10.0;

	public function new(zoom = 1.0, panX = 0.0, panY = 0.0) {
		this.zoom.set(zoom);
		this.panX.set(panX);
		this.panY.set(panY);
	}

	/** From content to screen coordinates. **/
	public function transform():Affine {
		var z = zoom.get();
		return new Affine(z, 0, 0, z, z * panX.get(), z * panY.get());
	}

	public function contentToScreen(x:Float, y:Float):{x:Float, y:Float} {
		var z = zoom.get();
		return {x: z * (x + panX.get()), y: z * (y + panY.get())};
	}

	public function screenToContent(x:Float, y:Float):{x:Float, y:Float} {
		var z = zoom.get();
		return {x: x / z - panX.get(), y: y / z - panY.get()};
	}

	/** Moves the content by `dx`, `dy` screen pixels. **/
	public function panBy(dx:Float, dy:Float):Void {
		var z = zoom.get();
		panX.set(panX.get() + dx / z);
		panY.set(panY.get() + dy / z);
	}

	/**
		Zooms by `factor` about the screen point `(x, y)`: the content under
		it stays under it, as zooming toward the cursor or a pinch does. The
		zoom stays within `minZoom` and `maxZoom`.
	**/
	public function zoomAt(x:Float, y:Float, factor:Float):Void {
		var before = screenToContent(x, y);
		var z = Math.max(minZoom, Math.min(maxZoom, zoom.get() * factor));
		zoom.set(z);
		panX.set(x / z - before.x);
		panY.set(y / z - before.y);
	}

	/**
		The pan and zoom that show the content rect `(x, y, width, height)`
		whole and centred in a `screenWidth` × `screenHeight` view, with
		`margin` of the view left round it on every side (0.12 by default).
	**/
	public function fitting(x:Float, y:Float, width:Float, height:Float, screenWidth:Float, screenHeight:Float,
			margin = 0.12):{panX:Float, panY:Float, zoom:Float} {
		var room = 1 - 2 * margin;
		var z = Math.min(screenWidth * room / Math.max(width, 1e-6), screenHeight * room / Math.max(height, 1e-6));
		z = Math.max(minZoom, Math.min(maxZoom, z));
		return {panX: screenWidth / 2 / z - (x + width / 2), panY: screenHeight / 2 / z - (y + height / 2), zoom: z};
	}

	/**
		Shows the content rect whole, as `fitting` places it, easing there
		over `seconds` (0 jumps) on the animation scheduler's clock.
	**/
	public function fit(x:Float, y:Float, width:Float, height:Float, screenWidth:Float, screenHeight:Float, seconds = 0.26, margin = 0.12):Void {
		var to = fitting(x, y, width, height, screenWidth, screenHeight, margin);
		moveTo(to.panX, to.panY, to.zoom, seconds);
	}

	/**
		Eases pan and zoom to these over `seconds` with an ease-out curve;
		0 jumps there. The zoom eases in its logarithm, so a large change in
		zoom looks even. A pan or zoom by hand meanwhile stops it.
	**/
	public function moveTo(toPanX:Float, toPanY:Float, toZoom:Float, seconds = 0.26):Void {
		moving++;
		if (seconds <= 0) {
			panX.set(toPanX);
			panY.set(toPanY);
			zoom.set(toZoom);
			return;
		}
		var run = moving;
		var fromX = panX.get(), fromY = panY.get(), fromZoom = Math.log(zoom.get()), endZoom = Math.log(toZoom);
		var t = 0.0;
		ashui.animation.AnimationScheduler.main.addTicker(dt -> {
			if (run != moving)
				return false;
			t = Math.min(1, t + dt / seconds);
			var k = 1 - Math.pow(1 - t, 3);
			panX.set(fromX + (toPanX - fromX) * k);
			panY.set(fromY + (toPanY - fromY) * k);
			zoom.set(Math.exp(fromZoom + (endZoom - fromZoom) * k));
			return t < 1;
		});
	}

	/** Stops a `moveTo` or `fit` under way. **/
	public function stop():Void
		moving++;

	/** Counts the moves begun, so a later one, or a stop, ends an earlier one. **/
	var moving = 0;

	/** Back to no pan and a zoom of 1. **/
	public function reset(seconds = 0.0):Void
		moveTo(0, 0, 1, seconds);
}
