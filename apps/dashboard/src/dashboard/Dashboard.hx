package dashboard;

import ashui.canvaskit.SceneKit;
import ashui.components.ToggleSwitch;
import ashui.layout.Element;
import ashui.reactive.Computed;
import ashui.types.Style;
import dashboard.Widgets.*;

/**
	The whole dashboard: one 3D scene behind everything, the car on its floor under the sky, and over it the page the
	driver is on, the island across the top and the dock along the bottom. The scene is drawn only on the pages that show
	the car, and the pages are made when they are opened, so a page nobody is on costs nothing.
**/
class Dashboard {
	public final model = new Model();
	public final music = new Music();
	public final screen = new Screen();

	final stage:Stage;
	final map:StreetMap;
	final vehicle:VehicleView;
	final media:MediaView;
	final navigate:NavigateView;
	final charging:ChargingView;
	final camera:CameraView;
	final phoneView:PhoneView;
	final profileView:ProfileView;
	final moreView:MoreView;
	public final phone = new Phone();
	final islandWidth:Void->Float;

	public function new() {
		stage = new Stage(Paint.ALL[model.paint.get()], toon());
		map = new StreetMap("assets/map/kings-cross.json", "assets/map/car-top.png");
		vehicle = new VehicleView(model, stage, screen, map);
		media = new MediaView(model, music, screen);
		navigate = new NavigateView(model, map, screen);
		charging = new ChargingView(model);
		camera = new CameraView(model, stage, screen);
		phoneView = new PhoneView(phone);
		profileView = new ProfileView(model);
		moreView = new MoreView(model);
		islandWidth = () -> screen.width.get();
	}

	static function toon():Bool {
		var v = Sys.getEnv("TOON");
		return v != "0";
	}

	function scene(inView:Computed<Bool>):Element {
		// The paint is applied as the scene is drawn: a reaction to the signal runs after the draw is recorded, a selection late.
		var draw = (ctx:ashui.draw.DrawContext) -> {
			var p = Paint.ALL[model.paint.get()];
			stage.car.setPaint(p.color, p.metallic);
			stage.draw(ctx);
		};
		return <div position={Absolute} left={0} top={0} widthPercent={1} heightPercent={1} hidden={Computed.make(() -> !inView.get())}>
			<scene-kit camera={stage.camera} lights={stage.lights} environment={stage.environment} environmentIntensity={stage.intensity}
				background={stage.background} fog={stage.fog} skybox={stage.skybox} shadows={true}
				shadowStrength={Computed.make(() -> stage.dark.get() ? 0.6 : 0.45)} shadowReach={4.5} draw={draw} widthPercent={1} heightPercent={1} />
		</div>;
	}

	function page(tab:Tab):Element
		return switch tab {
			case Vehicle: vehicle.build();
			case Media: media.build();
			case Navigate: navigate.build();
			case Charging: charging.build();
			case Camera: camera.build();
			case Phone: phoneView.build();
			case Profile: profileView.build();
			case More: moreView.build();
			case _: <div position={Absolute} left={0} top={0} widthPercent={1} heightPercent={1} class="flex items-center justify-center">
					<text class="text-2xl font-semibold">${Std.string(tab)}</text>
				</div>;
		}

	public function build():Element {
		model.run();
		var showsCar = Computed.make(() -> model.tab.get() == Vehicle || model.tab.get() == Camera);
		var root = <div class="dash-root" widthPercent={1} heightPercent={1}>
			{scene(showsCar)}
			<canvas widthPercent={1} heightPercent={1} position={Absolute} left={0} top={0} pointerEvents={PointerEvents.None} ref={screenProbe} />
			<for {tab in [model.tab.get()]}>{page(tab)}</for>
			{Island.build(islandWidth, model, music)}
			{Dock.build(model, screen)}
		</div>;
		// What the pages lay themselves out by is the size the probe has.
		new ashui.reactive.Watch(() -> screenProbe.get(), c -> if (c != null) screen.follow(c));
		return root;
	}

	final screenProbe = new ashui.ui.Ref<ashui.ui.Canvas>();
}
