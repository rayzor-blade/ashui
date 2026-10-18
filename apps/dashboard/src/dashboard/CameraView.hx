package dashboard;

import ashui.components.ToggleSwitch;
import ashui.icons.Remix;
import ashui.layout.Element;
import ashui.reactive.Computed;
import ashui.reactive.Signal;
import ashui.types.Style;
import dashboard.Widgets.*;

/**
	The Camera page: the car seen from the front, the rear, either side and from above, the cameras of a parking view. Each
	moves the same camera round the same car, so the view is where the car is, and a drag turns it from there. The sensors
	say how close the car is to what is round it.
**/
class CameraView {
	static final VIEWS = [
		{name: "Front", azimuth: Math.PI, elevation: 0.08, distance: 8.5},
		{name: "Rear", azimuth: 0.0, elevation: 0.08, distance: 8.5},
		{name: "Left", azimuth: -Math.PI / 2, elevation: 0.05, distance: 9.5},
		{name: "Right", azimuth: Math.PI / 2, elevation: 0.05, distance: 9.5},
		{name: "Surround", azimuth: -Math.PI / 2, elevation: 1.5, distance: 13.0}
	];

	final m:Model;
	final stage:Stage;
	final screen:Screen;
	final view = Signal.make(-1);
	final recording = Signal.make(false);
	final assist = Signal.make(true);

	public function new(m:Model, stage:Stage, screen:Screen) {
		this.m = m;
		this.stage = stage;
		this.screen = screen;
	}

	function choose(i:Int):Void {
		view.set(i);
		var v = VIEWS[i];
		stage.look(v.azimuth, v.elevation, v.distance);
	}

	function sensor(label:String, metres:Float):Element {
		var tone = metres < 0.7 ? "warn" : "good";
		var value = <text class="text-sm font-semibold">${Std.string(Math.round(m.distance(metres) * 10) / 10) + " " + (m.miles.get() ? "yd" : "m")}</text>;
		return <div class="flex flex-row items-center justify-between">
			<text class="text-sm ink-2">${label}</text>
			{value}
		</div>;
	}

	function recordKey():Element {
		var dot = flag(<div class="dash-rec" width={10} height={10} />, "on", () -> recording.get());
		return press(<div class="dash-tile flex flex-row items-center gap-2 px-3" height={40}>{dot}
			<text class="text-sm font-medium">${recording.get() ? "Recording dashcam" : "Record dashcam"}</text></div>, () -> recording.set(!recording.get()));
	}

	public function build():Element {
		var picker = segments([for (v in VIEWS) v.name], () -> view.get(), choose);
		function panel()
			return <div class="dash-glass flex flex-col gap-4 p-4" width={280}>
			<text class="dash-title">Sensors</text>
			{sensor("Front", 1.2)}{sensor("Rear", 0.9)}{sensor("Left", 0.6)}{sensor("Right", 1.5)}
			<div class="flex flex-row items-center justify-between">
				<text class="text-sm font-medium">Parking assist</text>
				<toggle-switch checked={assist} />
			</div>
			{recordKey()}
		</div>;
		// The page has no size of its own, so the car's scene takes the pointer wherever a part of it is not over.
		var top = Computed.make(() -> screen.height.get() - 144);
		return <div position={Absolute} left={0} top={0} width={0} height={0}>
			<div position={Absolute} left={0} top={78} width={screen.width} flexDirection={Row} justifyContent={Justify.Center}>{picker}</div>
			<if {screen.width.get() >= 820}>
				<div position={Absolute} left={24} top={120}>{panel()}</div>
			</if>
			<div position={Absolute} left={0} top={top} width={screen.width} flexDirection={Row} justifyContent={Justify.Center} pointerEvents={PointerEvents.None}>
				<div class="dash-chip flex flex-row items-center gap-2 px-3" height={36}>
					{icon(Remix.EYE_LINE, "size-4")}<text class="text-xs ink-2">Drag to look round the car · scroll to move closer</text>
				</div>
			</div>
		</div>;
	}
}
