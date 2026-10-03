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
	var opened = 0.0;
	/** Whether the input method is on: while text has focus. **/
	var imeOn = false;
	/** Whether the input method is composing, so key events bring no text of their own. **/
	var composing = false;
	/** A commit was just typed; the key events of this batch bring nothing more. **/
	var committed = false;
	// Pointer moves and wheel deltas waiting to be applied: a batch of events
	// collapses to the last position and the summed delta, as browsers do.
	var pendingMove:Null<{x:Float, y:Float}> = null;
	var pendingWheelX = 0.0;
	var pendingWheelY = 0.0;
	var pendingWheel = false;
	var modifiers:window.Modifiers = ashui.input.Events.InputEvent.NO_MODIFIERS;

	/** `ASHUI_FRAME_LOG=<file>` writes each frame's phase timings and each wheel delta there; off when unset, safe either way. **/
	final frameLog:Null<sys.io.FileOutput> = {
		var path = Sys.getEnv("ASHUI_FRAME_LOG");
		path != null && path != "" ? sys.io.File.write(path, false) : null;
	};

	/** The longest step animations advance by in one tick, in seconds. **/
	static inline var MAX_STEP = 0.05;

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
		// Raw device motion is not used, and a moving mouse sends a lot of it.
		Window.listenDeviceEvents(Never);
		var window = Window.open(attributes);
		if (!window.valid())
			throw "the window could not be opened";
		// An app started from a terminal or another process is not made active on its own.
		window.focus();
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
		ashui.input.WindowState.active.set(window.hasFocus());
		// The input method is on while text has focus, its candidates by the caret.
		new ashui.reactive.Watch(() -> ashui.input.WindowState.textCaret.get(), area -> {
			var on = area != null;
			if (on != imeOn) {
				imeOn = on;
				window.setImeAllowed(on);
			}
			if (area != null)
				window.setImeCursorArea(area.x, area.y, area.width, area.height);
		}, (a, b) -> a == b || (a != null && b != null && a.x == b.x && a.y == b.y && a.width == b.width && a.height == b.height));
		configure();
		root = Owner.root(tree, _ -> build());
		opened = haxe.Timer.stamp();
		var last = opened;
		var presented = opened;
		if (frameLog != null)
			frameLog.writeString("frame\tat_ms\tsince_last_frame\twait\tevents\tn_events\ttick\tflush\tdraw_flush\tlayout\tlist\tgpu\tpresent\tprimitives\n");
		while (!quitting) {
			// No wait when a frame is already due, short ones while something
			// animates; otherwise the loop sleeps on the window, until the next timer at most.
			var animating = scheduler.hasActive();
			var timer = scheduler.untilNextTimer();
			var t0 = haxe.Timer.stamp();
			var due = dirty && ashui.input.WindowState.visible.get();
			var event = due ? window.poll() : window.wait(animating ? 1 / 120 : timer != null ? Math.min(0.1, timer) : 0.1);
			var t1 = haxe.Timer.stamp();
			var handled = 0;
			var polling = 0.0;
			var kinds = frameLog != null ? new Map<String, Int>() : null;
			while (event != None) {
				if (kinds != null) {
					var k = Type.enumConstructor(event);
					kinds.set(k, (kinds.exists(k) ? kinds.get(k) : 0) + 1);
				}
				handle(event);
				handled++;
				var p0 = haxe.Timer.stamp();
				event = window.poll();
				polling += haxe.Timer.stamp() - p0;
			}
			applyPointer();
			if (committed) {
				committed = false;
				composing = false;
			}
			if (kinds != null && handled > 0)
				frameLog.writeString('events\t${Math.round((haxe.Timer.stamp() - opened) * 10000) / 10}\tpoll_ms=${Math.round(polling * 10000) / 10}\t${[for (k => n in kinds) '$k=$n'].join(" ")}\n');
			var now = haxe.Timer.stamp();
			// Capped, so after a stall an animation carries on from where it was instead of jumping ahead.
			scheduler.tick(Math.min(now - last, MAX_STEP));
			last = now;
			if (theme.tick() || animating)
				dirty = true;
			var t2 = haxe.Timer.stamp();
			if (tree.flush()) {
				dirty = true;
				// Layout may have moved something under a still pointer.
				ashui.input.Pointer.refresh(tree);
			}
			var t3 = haxe.Timer.stamp();
			// A hidden window draws nothing; what changes waits for it to show again.
			if (dirty && !quitting && ashui.input.WindowState.visible.get()) {
				dirty = false;
				if (draw()) {
					frames++;
					var t4 = haxe.Timer.stamp();
					if (frameLog != null) {
						var o = offscreen.timings;
						inline function ms(s:Float)
							return Std.string(Math.round(s * 10000) / 10);
						frameLog.writeString([
							Std.string(frames), ms(t4 - opened), ms(t4 - presented), ms(t1 - t0), ms(now - t1), Std.string(handled), ms(t2 - now),
							ms(t3 - t2), ms(o.flush), ms(o.layout), ms(o.list), ms(o.draw), ms(t4 - t3 - o.flush - o.layout - o.list - o.draw),
							Std.string(offscreen.primitives)
						].join("\t") + "\n");
						frameLog.flush();
					}
					presented = t4;
					if (onFrame != null)
						onFrame(frames, haxe.Timer.stamp() - opened);
				}
			}
		}
		if (frameLog != null)
			frameLog.close();
		ThemeState.setRedrawCallback(null);
		theme.setScheduler(null);
	}

	/** Applies the batch's last pointer position, then its summed wheel delta. **/
	function applyPointer():Void {
		if (pendingMove != null) {
			var at = pendingMove;
			pendingMove = null;
			ashui.input.Pointer.move(tree, at.x, at.y, modifiers);
		}
		if (pendingWheel) {
			pendingWheel = false;
			var dx = pendingWheelX, dy = pendingWheelY;
			pendingWheelX = pendingWheelY = 0;
			ashui.input.Pointer.wheel(tree, dx, dy);
		}
	}

	function handle(event:window.Event):Void {
		// Moves and wheel deltas wait for the end of the batch; anything else
		// sees them applied first, so a press lands where the pointer is.
		switch event {
			case CursorMoved(_, _, _) | MouseWheel(_, _, _):
			case _:
				applyPointer();
		}
		switch event {
			case Closed | Destroyed:
				quitting = true;
			case Resized(_, _) | ScaleFactorChanged(_):
				configure();
				dirty = true;
			case ThemeChanged(_):
				WindowTheme.handle(event);
			case Focused(on):
				if (ashui.input.WindowState.active.get() != on)
					ashui.input.WindowState.active.set(on);
			case Occluded(hidden):
				if (ashui.input.WindowState.visible.get() == hidden)
					ashui.input.WindowState.visible.set(!hidden);
				// Coming back into view draws what changed meanwhile.
				if (!hidden)
					dirty = true;
			case RedrawRequested:
				dirty = true;
			case CursorMoved(x, y, _):
				var scale = window.scaleFactor();
				pendingMove = {x: x / scale, y: y / scale};
			case CursorLeft(_):
				ashui.input.Pointer.leave(tree);
			case MouseInput(state, button, _):
				// Input reaches only the active window, whatever the focus events said.
				activeByInput();
				if (state == Pressed)
					ashui.input.Pointer.press(tree, button);
				else
					ashui.input.Pointer.release(tree, button);
			case MouseWheel(delta, phase, _):
				if (frameLog != null) {
					var d = switch delta {
						case LineDelta(x, y): '$x\t$y\tlines';
						case PixelDelta(x, y): '$x\t$y\tpixels';
					};
					frameLog.writeString('wheel\t${Math.round((haxe.Timer.stamp() - opened) * 10000) / 10}\t$d\t$phase\n');
				}
				// Applied after the batch's last move: during a scroll the pointer barely moves.
				pendingWheel = true;
				switch delta {
					case LineDelta(x, y):
						pendingWheelX += x * WHEEL_LINE;
						pendingWheelY += y * WHEEL_LINE;
					case PixelDelta(x, y):
						var scale = window.scaleFactor();
						pendingWheelX += x / scale;
						pendingWheelY += y / scale;
				}
			case ModifiersChanged(m):
				modifiers = m;
				ashui.input.Pointer.modifiers(tree, m);
			case KeyboardInput(_, key, _):
				activeByInput();
				ashui.input.Keyboard.input(tree, key, modifiers);
				// A key's text is typed unless a shortcut modifier is held or it is a control
				// character. While an input method composes, its commit brings the text instead;
				// plain typing comes on key events even with the input method on.
				switch key {
					case Input(_, _, Some(text), _, Pressed, _, _) if (!composing && !shortcut() && text.charCodeAt(0) >= 0x20 && text.charCodeAt(0) != 0x7f):
						ashui.input.Keyboard.text(tree, text, modifiers);
					case _:
				}
			case Ime(Preedit(text, cursor)):
				composing = text != "";
				ashui.input.Keyboard.composition(tree, text, switch cursor {
					case Range(start, _): utf16Index(text, haxe.Int64.toInt(start));
					case None: -1;
				});
			case Ime(Commit(text)):
				ashui.input.Keyboard.composition(tree, "", -1);
				ashui.input.Keyboard.text(tree, text, modifiers);
				// The key that commits may also bring its text; it is typed already.
				composing = true;
				committed = true;
			case Ime(Disabled):
				composing = false;
				ashui.input.Keyboard.composition(tree, "", -1);
			case _:
		}
	}

	/** The string index of UTF-8 byte offset `byte` in `text`, as the input method reports its caret. **/
	static function utf16Index(text:String, byte:Int):Int {
		var bytes = 0;
		var i = 0;
		while (i < text.length && bytes < byte) {
			var c = StringTools.fastCodeAt(text, i);
			// A surrogate pair is one character of four bytes.
			if (c >= 0xD800 && c <= 0xDBFF) {
				bytes += 4;
				i += 2;
			} else {
				bytes += c < 0x80 ? 1 : c < 0x800 ? 2 : 3;
				i++;
			}
		}
		return i;
	}

	function activeByInput():Void {
		if (!ashui.input.WindowState.active.get())
			ashui.input.WindowState.active.set(true);
	}

	function shortcut():Bool
		return switch modifiers {
			case State(_, control, _, superKey, _, _, _, _, _, _, _, _): control || superKey;
		}

	/** Draws the tree into the window's next frame and presents it; false when the surface had none. **/
	function draw():Bool {
		var view = surface.acquire();
		if (!view.valid()) {
			if (frameLog != null)
				frameLog.writeString('noframe\t${Math.round((haxe.Timer.stamp() - opened) * 10000) / 10}\twindow=${window.width()}x${window.height()}\n');
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
		configuration.presentMode(presentMode());
		var capabilities = surface.capabilities(adapter);
		configuration.alphaMode(capabilities.alphaMode(0));
		device.configureSurfaceWith(surface, configuration);
	}

	/** `ASHUI_PRESENT_MODE=fifo|fifo-relaxed|mailbox|immediate` picks the present mode, Fifo by default; one the surface lacks fails at configure. **/
	static function presentMode():gpu.PresentMode {
		return switch Sys.getEnv("ASHUI_PRESENT_MODE") {
			case "fifo-relaxed": FifoRelaxed;
			case "mailbox": Mailbox;
			case "immediate": Immediate;
			case _: Fifo;
		}
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
