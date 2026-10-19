package dashboard;

import ashui.reactive.Computed;
import ashui.reactive.Signal;
import ashui.reactive.Watch;

/**
	How much room the dashboard has: its laid-out size, read from a canvas that fills it. The stylesheet makes the layout larger
	than a small window (`--ui-zoom` under `@media`), so the pages always have room for everything and draw it at any size.
**/
class Screen {
	public final width = Signal.make(1600.0);
	public final height = Signal.make(820.0);

	/** The dock's labels have room. **/
	public final labelled:Computed<Bool>;

	public function new() {
		labelled = Computed.make(() -> width.get() >= 700);
	}

	/** Follows `canvas`, which fills the dashboard. **/
	public function follow(canvas:ashui.ui.Canvas):Void {
		new Watch(() -> canvas.laidWidth(), w -> if (w > 0) width.set(w));
		new Watch(() -> canvas.laidHeight(), h -> if (h > 0) height.set(h));
	}
}
