package ashui.app;

#if (hlwindow || ashui_window)
import ashui.animation.AnimationScheduler;
import ashui.core.render.Offscreen;
import ashui.layout.Element;
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.theme.Platform;
import ashui.theme.ThemeBundle;
import ashui.theme.ThemeState;
import ashui.theme.WindowTheme;
import gpu.GpuAdapter;
import gpu.GpuDevice;
import gpu.GpuInstance;
import gpu.GpuSurface;
import gpu.GpuSurfaceConfiguration;
import gpu.Power;
import gpu.TextureFormat;
import window.Window;
import window.WindowAttributes;

typedef WindowConfig = {
	?title:String,
	/** The inner size in logical pixels. **/
	?width:Int,
	?height:Int,
	?resizable:Bool,
	/** The theme to install when none is; the default theme otherwise. **/
	?theme:ThemeBundle,
	/** Called after each presented frame with its number and the seconds since the window opened. **/
	?onFrame:(frame:Int, seconds:Float) -> Void
}

/**
	Opens a window and draws a UI into it until the window closes, as Blinc's
	`WindowedApp` does. A frame is drawn only when something changed: the
	tree on flush, the theme (a scheme transition draws until it settles),
	the window's size or scale. Between frames the loop waits on the
	window's events. The scheme follows the window's appearance. The
	pointer, wheel, keys and typed text go to the UI through
	`ashui.input.Pointer` and `ashui.input.Keyboard`.
**/
class WindowedApp {
	/** The running app, if any. **/
	public static var current(default, null):Null<WindowedApp>;

	public final window:Window;
	public final device:GpuDevice;
	public final offscreen:Offscreen;
	public final tree:LayoutTree;
	public var frames(default, null) = 0;

	final adapter:GpuAdapter;
	final surface:GpuSurface;
	final format:TextureFormat;
	final scheduler = AnimationScheduler.main;
	var root:Element;
	var dirty = true;
	var quitting = false;
	var modifiers:window.Modifiers = ashui.input.Events.InputEvent.NO_MODIFIERS;

	/** Layout units a wheel scrolls by for each line it reports. **/
	static inline var WHEEL_LINE = 40.0;

	/** Runs `build`'s UI in a window until it closes or `quit` is called. Returns the frames presented. **/
	public static function run(config:WindowConfig, build:Void->Element):Int {
		if (ThemeState.tryGet() == null)
			ThemeState.init(config.theme != null ? config.theme : ashui.theme.themes.DefaultTheme.bundle(), Platform.detectSystemColorScheme());
		var instance = new GpuInstance();
		// The device comes first: an await does not wake on Ash once a window is open (ash 4855ac5).
		var adapter = instance.requestAdapter(Power.HighPerformance).await();
		var device = adapter.requestDevice().await();
		var attributes = new WindowAttributes();
		attributes.title(config.title != null ? config.title : "ashui");
		attributes.width(config.width != null ? config.width : 800);
		attributes.height(config.height != null ? config.height : 600);
		attributes.resizable(config.resizable != false);
		var window = Window.open(attributes);
		if (!window.valid())
			throw "the window could not be opened";
		var surface = instance.surface(window.platform(), window.raw(0), window.raw(1), window.raw(2), window.raw(3));
		if (!surface.valid())
			throw 'platform ${window.platform()} gave no GPU surface';
		var app = new WindowedApp(window, adapter, device, surface);
		current = app;
		try {
			app.loop(build, config.onFrame);
		} catch (e:haxe.Exception) {
			app.close(instance);
			throw e;
		}
		app.close(instance);
		return app.frames;
	}

	function new(window:Window, adapter:GpuAdapter, device:GpuDevice, surface:GpuSurface) {
		this.window = window;
		this.adapter = adapter;
		this.device = device;
		this.surface = surface;
		format = chooseFormat();
		offscreen = new Offscreen(device, format);
		tree = new LayoutTree();
	}

	/** Closes the window after the frame being drawn. **/
	public function quit():Void {
		quitting = true;
	}

	/** Draws a frame at the next chance, for a change the app knows of and the tree does not. **/
	public function invalidate():Void {
		dirty = true;
	}

	/** Width and height in logical pixels, which the UI is laid out in. **/
	public function logicalWidth():Int
		return Math.round(window.width() / window.scaleFactor());

	public function logicalHeight():Int
		return Math.round(window.height() / window.scaleFactor());

	function loop(build:Void->Element, onFrame:Null<(Int, Float) -> Void>):Void {
		var theme = ThemeState.get();
		theme.setScheduler(scheduler);
		ThemeState.setRedrawCallback(() -> dirty = true);
		WindowTheme.follow(window);
		configure();
		root = Owner.root(tree, _ -> build());
		var opened = haxe.Timer.stamp();
		var last = opened;
		while (!quitting) {
			// No wait when a frame is already due, short ones while something
			// animates; otherwise the loop sleeps on the window.
			var animating = scheduler.hasActive();
			var event = dirty ? window.poll() : window.wait(animating ? 1 / 120 : 0.1);
			while (event != None) {
				handle(event);
				event = window.poll();
			}
			var now = haxe.Timer.stamp();
			scheduler.tick(now - last);
			last = now;
			if (theme.tick() || animating)
				dirty = true;
			if (tree.flush()) {
				dirty = true;
				// Layout may have moved something under a still pointer.
				ashui.input.Pointer.refresh(tree);
			}
			if (dirty && !quitting) {
				dirty = false;
				if (draw()) {
					frames++;
					if (onFrame != null)
						onFrame(frames, haxe.Timer.stamp() - opened);
				}
			}
		}
		ThemeState.setRedrawCallback(null);
		theme.setScheduler(null);
	}

	function handle(event:window.Event):Void {
		switch event {
			case Closed | Destroyed:
				quitting = true;
			case Resized(_, _) | ScaleFactorChanged(_):
				configure();
				dirty = true;
			case ThemeChanged(_):
				WindowTheme.handle(event);
			case RedrawRequested:
				dirty = true;
			case CursorMoved(x, y, _):
				var scale = window.scaleFactor();
				ashui.input.Pointer.move(tree, x / scale, y / scale, modifiers);
			case CursorLeft(_):
				ashui.input.Pointer.leave(tree);
			case MouseInput(state, button, _):
				if (state == Pressed)
					ashui.input.Pointer.press(tree, button);
				else
					ashui.input.Pointer.release(tree, button);
			case MouseWheel(delta, _, _):
				switch delta {
					case LineDelta(x, y):
						ashui.input.Pointer.wheel(tree, x * WHEEL_LINE, y * WHEEL_LINE);
					case PixelDelta(x, y):
						var scale = window.scaleFactor();
						ashui.input.Pointer.wheel(tree, x / scale, y / scale);
				}
			case ModifiersChanged(m):
				modifiers = m;
				ashui.input.Pointer.modifiers(tree, m);
			case KeyboardInput(_, key, _):
				ashui.input.Keyboard.input(tree, key, modifiers);
				// A key's text is typed unless a shortcut modifier is held or it is a control character.
				switch key {
					case Input(_, _, Some(text), _, Pressed, _, _) if (!shortcut() && text.charCodeAt(0) >= 0x20 && text.charCodeAt(0) != 0x7f):
						ashui.input.Keyboard.text(tree, text, modifiers);
					case _:
				}
			case Ime(Commit(text)):
				ashui.input.Keyboard.text(tree, text, modifiers);
			case _:
		}
	}

	function shortcut():Bool
		return switch modifiers {
			case State(_, control, _, superKey, _, _, _, _, _, _, _, _): control || superKey;
		}

	/** Draws the tree into the window's next frame and presents it; false when the surface had none. **/
	function draw():Bool {
		var view = surface.acquire();
		if (!view.valid()) {
			configure();
			dirty = true;
			return false;
		}
		var background = ThemeState.get().color(Background);
		offscreen.clear = background.rgb();
		offscreen.clearAlpha = background.a;
		offscreen.scale = window.scaleFactor();
		offscreen.render(root, view, logicalWidth(), logicalHeight());
		device.queue().presentSurface(surface);
		return true;
	}

	/** Sizes the surface to the window's physical pixels. **/
	function configure():Void {
		if (window.width() <= 0 || window.height() <= 0)
			return;
		var configuration = new GpuSurfaceConfiguration(format, window.width(), window.height());
		configuration.presentMode(Fifo);
		var capabilities = surface.capabilities(adapter);
		configuration.alphaMode(capabilities.alphaMode(0));
		device.configureSurfaceWith(surface, configuration);
	}

	/** A format without sRGB encoding, as Blinc picks: the theme's colours are already in sRGB. **/
	function chooseFormat():TextureFormat {
		var capabilities = surface.capabilities(adapter);
		for (wanted in [TextureFormat.Bgra8unorm, TextureFormat.Rgba8unorm])
			for (i in 0...capabilities.formatCount())
				if (capabilities.format(i) == wanted)
					return wanted;
		return surface.preferredFormat(adapter);
	}

	function close(instance:GpuInstance):Void {
		if (current == this)
			current = null;
		surface.destroy();
		device.destroy();
		adapter.destroy();
		instance.destroy();
		window.close();
	}
}
#end
