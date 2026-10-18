package dashboard;

import ashui.reactive.Computed;
import ashui.reactive.Signal;
import ashui.reactive.Watch;

/**
	How much room the dashboard has: its laid-out size, read from a canvas that fills it, and what the pages do with it. A
	wide window has both side columns of panels, a medium one the two that matter, a narrow one none, and a small one drops
	the dock's labels.
**/
class Screen {
	public final width = Signal.make(1600.0);
	public final height = Signal.make(820.0);

	/** Both columns of panels fit beside the car. **/
	public final wide:Computed<Bool>;

	/** One panel each side fits. **/
	public final medium:Computed<Bool>;

	/** The dock's labels have room. **/
	public final labelled:Computed<Bool>;

	public function new() {
		wide = Computed.make(() -> width.get() >= 1240 && height.get() >= 860);
		medium = Computed.make(() -> width.get() >= 900 && height.get() >= 560);
		labelled = Computed.make(() -> width.get() >= 700);
	}

	/** Follows `canvas`, which fills the dashboard. **/
	public function follow(canvas:ashui.ui.Canvas):Void {
		new Watch(() -> canvas.laidWidth(), w -> if (w > 0) width.set(w));
		new Watch(() -> canvas.laidHeight(), h -> if (h > 0) height.set(h));
	}
}
