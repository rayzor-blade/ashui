package ashui.app;

#if (hlwindow || ashui_window)
import ashui.animation.AnimationScheduler;
import ashui.core.render.Offscreen;
import ashui.layout.Element;
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.theme.Platform;
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

/**
	Opens a window and draws a UI into it until the window closes. `run`
	takes the window's settings and a function that builds the root
	element:

	    WindowedApp.run({title: "ashui", width: 640, height: 480}, page);

	A frame is drawn only when something changed: the tree on flush, the
	theme (a scheme transition draws until it settles), the window's size
	or scale. Between frames the loop waits on the window's events. The
	scheme follows the window's appearance. The pointer, wheel, keys and
	typed text go to the UI through `ashui.input.Pointer` and
	`ashui.input.Keyboard`. Blinc's `WindowedApp` does the same.
**/
class WindowedApp {
	/** The running app, if any. **/
	public static var current(default, null):Null<WindowedApp>;

	public final window:Window;
	public final device:GpuDevice;
	/** What draws the tree into the window's frames. **/
	public final offscreen:Offscreen;
	/** The tree the UI `build` made lives in. **/
	public final tree:LayoutTree;
	/** Frames presented so far. **/
	public var frames(default, null) = 0;

	final adapter:GpuAdapter;
	/** What is under the window shows where the UI draws nothing. **/
	final transparent:Bool;
	final surface:GpuSurface;
	final format:TextureFormat;
	final scheduler = AnimationScheduler.main;
	var root:Element;
	var dirty = true;
	var quitting = false;
	/**
		On Wayland a frame waits for the compositor's frame callback for the
		last, which paces frames to the display (see `presentMode`).
		Elsewhere Fifo's present paces them, and the redraw may not come for a
		window out of view.
	**/
	final paceOnRedraw:Bool;

	/** A frame is presented and the redraw asked for after it has not come: nothing is drawn until it does. **/
	var awaitingFrame = false;
	var awaitingSince = 0.0;
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

	/** `ASHUI_WINDOW_SECONDS=<n>` closes the window after that many seconds, for benches and scripted runs; off when unset. **/
	final closeAfter:Float = {
		var s = Std.parseFloat(Sys.getEnv("ASHUI_WINDOW_SECONDS"));
		Math.isNaN(s) || s <= 0 ? 0.0 : s;
	};

	/** `ASHUI_INPUT_LOG=<path>` records the window's input and writes it to the path when the loop ends (see `ashui.debug.InputLog`). **/
	final inputLog:Null<String> = Sys.getEnv("ASHUI_INPUT_LOG");

	/** `ASHUI_MOTION=overlay` draws motion trails over the frames, `stream` also writes each burst of motion out for review (see `ashui.debug.MotionStream`). **/
	var motion:Null<ashui.debug.MotionStream> = null;

	/** hlwindow's platform code for Wayland. **/
	static inline var WAYLAND = 4;

	/** How long a frame waits for the redraw after the last before drawing anyway, in seconds: a compositor sends none to a window it does not show. **/
	static inline var FRAME_WAIT_LIMIT = 1.0;

	/** When the surface last gave no frame to draw into. **/
	var refusedAt = Math.NEGATIVE_INFINITY;

	/** How long after the surface gives no frame the next is asked for, in seconds. **/
	static inline var RETRY_FRAME = 0.016;

	/** Whether the last turn's animation ticks changed nothing drawn. **/
	var idleTicks = false;

	/** How long the loop waits between animation ticks that change nothing drawn, in seconds. **/
	static inline var IDLE_STEP = 0.05;

	/** The longest step animations advance by in one tick, in seconds. **/
	static inline var MAX_STEP = 0.05;

	/** Layout units a wheel scrolls by for each line it reports. **/
	static inline var WHEEL_LINE = 40.0;

	/** Runs `build`'s UI in a window until it closes or `quit` is called. Returns the frames presented. **/
	public static function run(settings:WindowConfig, build:Void->Element):Int {
		var config = settings.data;
		if (ThemeState.tryGet() == null)
			ThemeState.init(config.theme != null ? config.theme : ashui.theme.themes.DefaultTheme.bundle(), Platform.detectSystemColorScheme());
		var instance = new GpuInstance();
		// The device comes first: an await does not wake on Ash once a window is open.
		var adapter = instance.requestAdapter(Power.HighPerformance).await();
		var device = ashui.core.render.Renderer.requestDevice(adapter);
		var attributes = settings.attributes();
		// Raw device motion is not used, and a moving mouse sends a lot of it.
		Window.listenDeviceEvents(Never);
		var window = Window.open(attributes);
		if (!window.valid())
			throw "the window could not be opened";
		// An app started from a terminal or another process is not made active on its own.
		if (config.active != false)
			window.focus();
		var surface = instance.surface(window.platform(), window.raw(0), window.raw(1), window.raw(2), window.raw(3));
		if (!surface.valid())
			throw 'platform ${window.platform()} gave no GPU surface';
		var app = new WindowedApp(window, adapter, device, surface, config.transparent == true);
		current = app;
		try {
			app.loop(build, config.onFrame);
		} catch (e:haxe.Exception) {
			// Where it failed, which the rethrow below would report as here.
			Sys.stderr().writeString(e.details() + "\n");
			app.close(instance);
			throw e;
		}
		app.close(instance);
		return app.frames;
	}

	function new(window:Window, adapter:GpuAdapter, device:GpuDevice, surface:GpuSurface, transparent:Bool) {
		this.window = window;
		this.transparent = transparent;
		this.adapter = adapter;
		this.device = device;
		this.surface = surface;
		format = chooseFormat();
		offscreen = new Offscreen(device, format);
		motion = ashui.debug.MotionStream.fromEnvironment(offscreen);
		tree = new LayoutTree();
		paceOnRedraw = window.platform() == WAYLAND;
	}

	/** Closes the window after the frame being drawn. **/
	public function quit():Void {
		quitting = true;
		ashui.core.Work.notify();
	}

	/**
		Moves the window with the pointer from `press` until its button is
		released: a window with no title bar dragged by what it shows. Call
		it from a pointer-down handler. The system drags the window where it
		can, as it does by a title bar. Where it cannot, the window follows
		the pointer: it moves by as far as the pointer has on screen, so the
		press stays under the pointer.
	**/
	public function dragWith(press:ashui.input.Events.PointerEvent):Void {
		if (window.dragWindow())
			return;
		// In logical pixels, as layout and setPosition are; the window's position reads in physical ones.
		var scale = window.scaleFactor();
		var startX = window.x() / scale, startY = window.y() / scale;
		var fromX = startX + press.x, fromY = startY + press.y;
		var follow:Null<LayoutTree->Void> = null;
		follow = t -> if (t == tree) {
			var at = ashui.input.Pointer.at(tree);
			if (!at.pressed) {
				ashui.input.Pointer.hooks.remove(follow);
				return;
			}
			var x = window.x() / scale + at.x, y = window.y() / scale + at.y;
			window.setPosition(Math.round(startX + x - fromX), Math.round(startY + y - fromY));
		};
		ashui.input.Pointer.hooks.push(follow);
	}

	/** Draws a frame at the next chance, for a change the app knows of and the tree does not. **/
	public function invalidate():Void {
		dirty = true;
		ashui.core.Work.notify();
	}

	/** Width and height in logical pixels, which the UI is laid out in. **/
	public function logicalWidth():Int
		return Math.round(window.width() / window.scaleFactor());

	public function logicalHeight():Int
		return Math.round(window.height() / window.scaleFactor());

	function loop(build:Void->Element, onFrame:Null<(Int, Float) -> Void>):Void {
		ashui.core.Work.listen(() -> { Window.wake(); });
		var last = haxe.Timer.stamp();
		scheduler.useRealtime(motion == null);
		var theme = ThemeState.get();
		// The window's own scheme first, before there is a scheduler, so it applies at once rather than as a transition.
		WindowTheme.follow(window);
		theme.setScheduler(scheduler);
		ThemeState.setRedrawCallback(invalidate);
		ashui.input.WindowState.active.set(window.hasFocus());
		var log = inputLog != null && inputLog != "" ? ashui.debug.InputLog.start() : null;
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
		var presented = opened;
		if (frameLog != null)
			frameLog.writeString("frame\tat_ms\tsince_last_frame\twait\tevents\tn_events\ttick\tflush\tdraw_flush\tlayout\tlist\tgpu\tpresent\tprimitives\n");
		var closeAt = closeAfter > 0 ? haxe.Timer.stamp() + closeAfter : 0.0;
		while (!quitting) {
			if (closeAt > 0 && haxe.Timer.stamp() >= closeAt)
				break;
			// No wait when a frame is due; after a present, until its redraw;
			// short ones while something animates; otherwise the loop sleeps
			// on the window. Never past the next timer.
			var animating = scheduler.hasActive() || (motion != null && (motion.busy() || motion.overlay.shown().length > 0));
			var timer = scheduler.untilNextTimer();
			var t0 = haxe.Timer.stamp();
			if (awaitingFrame && t0 - awaitingSince > FRAME_WAIT_LIMIT)
				awaitingFrame = false;
			// After the surface gave no frame, the next try waits a little, rather than spinning while it has none to give.
			var due = dirty && ashui.input.WindowState.visible.get() && !awaitingFrame && t0 - refusedAt >= RETRY_FRAME;
			// While a frame is awaited the wait ends with its redraw; animation steps when it comes.
			// Animations that changed nothing drawn last turn, as those out of view, step slower, until one does or input comes.
			var timeout = awaitingFrame ? FRAME_WAIT_LIMIT - (t0 - awaitingSince) : animating ? (idleTicks ? IDLE_STEP : 1 / 120) : Math.POSITIVE_INFINITY;
			#if ashui_hot_reload
			// File watching uses a deadline only in builds that enable hot reload.
			timeout = Math.min(timeout, 0.1);
			#end
			if (dirty && t0 - refusedAt < RETRY_FRAME)
				timeout = Math.min(timeout, RETRY_FRAME - (t0 - refusedAt));
			if (timer != null)
				timeout = Math.min(timeout, timer);
			if (closeAt > 0)
				timeout = Math.max(0, Math.min(timeout, closeAt - t0));
			var event = due ? window.poll() : window.wait(timeout == Math.POSITIVE_INFINITY ? -1 : timeout);
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
			if (offscreen.hitMap != null && offscreen.hitMap.pointerChanged(tree))
				dirty = true;
			if (committed) {
				committed = false;
				composing = false;
			}
			if (kinds != null && handled > 0)
				frameLog.writeString('events\t${Math.round((haxe.Timer.stamp() - opened) * 10000) / 10}\tpoll_ms=${Math.round(polling * 10000) / 10}\t${[for (k => n in kinds) '$k=$n'].join(" ")}\n');
			#if ashui_hot_reload
			if (ashui.ui.HotReload.check())
				dirty = true;
			#end
			var now = haxe.Timer.stamp();
			// Capped, so after a stall an animation carries on from where it was instead of jumping ahead.
			var step = Math.min(now - last, MAX_STEP);
			if (motion != null && motion.busy()) {
				// While a burst is written, a fixed step per frame drawn: the capture's cost stays out of the motion.
				step = motion.step(step);
				scheduler.tick(step, step);
			} else
				scheduler.tick(step, now - last);
			last = now;
			// A frame is drawn for what changed: the theme, the motion overlay, or what the tree's flush reports below.
			// A ticker that changed nothing drawn, an animation out of view, draws nothing.
			if (theme.tick() || (motion != null && (motion.busy() || motion.overlay.shown().length > 0)))
				dirty = true;
			if (awaitingFrame && dirty) {
				coalescePointer();
				continue;
			}
			var t2 = haxe.Timer.stamp();
			var changed = tree.flush();
			idleTicks = animating && !changed && !dirty;
			if (changed)
				dirty = true;
			var t3 = haxe.Timer.stamp();
			// A hidden window draws nothing; what changes waits for it to show again.
			if (dirty && !quitting && ashui.input.WindowState.visible.get() && haxe.Timer.stamp() - refusedAt >= RETRY_FRAME) {
				dirty = false;
				if (draw()) {
					// Hit-test the new layout, including a still pointer. Hover
					// changes can require another frame after this one.
					if (ashui.input.Pointer.refresh(tree)) dirty = true;
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
					if (motion != null)
						motion.frame(tree, root, logicalWidth(), logicalHeight());
					if (onFrame != null)
						onFrame(frames, haxe.Timer.stamp() - opened);
				}
			}
			coalescePointer();
		}
		if (frameLog != null)
			frameLog.close();
		if (log != null) {
			log.stop();
			log.save(inputLog);
		}
		ThemeState.setRedrawCallback(null);
		theme.setScheduler(null);
	}

	/** Applies the batch's last pointer position, then its summed wheel delta. **/
	function applyPointer():Void {
		// Quiet native moves stay out of the event queue. Consume the latest
		// position and clear the filter before input or application work.
		switch window.takeCursorMove() {
			case CursorMoved(x, y, _):
				var scale = window.scaleFactor();
				pendingMove = {x: x / scale, y: y / scale};
			case _:
		}
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

	function coalescePointer():Void {
		var region = ashui.input.Pointer.quietRegion(tree);
		if (region == null) {
			window.coalesceCursorMoves(0, 0, 0, 0);
			return;
		}
		var scale = window.scaleFactor();
		window.coalesceCursorMoves(Math.max(0, region.left * scale), Math.max(0, region.top * scale),
			Math.min(window.width(), region.right * scale), Math.min(window.height(), region.bottom * scale));
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
				if (ashui.debug.InputLog.current != null)
					ashui.debug.InputLog.note(tree, ashui.debug.InputLog.InputRecord.WindowFocus(on));
				if (ashui.input.WindowState.active.get() != on)
					ashui.input.WindowState.active.set(on);
			case Occluded(hidden):
				if (ashui.input.WindowState.visible.get() == hidden)
					ashui.input.WindowState.visible.set(!hidden);
				// Coming back into view draws what changed meanwhile.
				if (!hidden)
					dirty = true;
			case RedrawRequested:
				// The one asked for after a present opens the next frame; any other asks for one.
				if (awaitingFrame)
					awaitingFrame = false;
				else
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
			refusedAt = haxe.Timer.stamp();
			return false;
		}
		var background = ThemeState.get().color(Background);
		offscreen.clear = transparent ? 0 : background.rgb();
		offscreen.clearAlpha = transparent ? 0 : background.a;
		offscreen.scale = window.scaleFactor();
		offscreen.targetWidth = window.width();
		offscreen.targetHeight = window.height();
		offscreen.render(root, view, logicalWidth(), logicalHeight());
		if (!paceOnRedraw) {
			device.queue().presentSurface(surface);
			return true;
		}
		// Asks for a frame callback for what is presented next; the redraw asked for after it waits for that callback.
		window.prePresentNotify();
		device.queue().presentSurface(surface);
		window.requestRedraw();
		awaitingFrame = true;
		awaitingSince = haxe.Timer.stamp();
		return true;
	}

	/** Sizes the surface to the window's physical pixels. **/
	function configure():Void {
		if (window.width() <= 0 || window.height() <= 0)
			return;
		var configuration = new GpuSurfaceConfiguration(format, window.width(), window.height());
		var capabilities = surface.capabilities(adapter);
		configuration.presentMode(presentMode(capabilities));
		configuration.alphaMode(alphaMode(capabilities));
		device.configureSurfaceWith(surface, configuration);
	}

	/**
		How the window's frames composite over what is under it: with their
		alpha when transparent, as the surface allows. Straight colours
		blended over a frame cleared to nothing come out premultiplied.
	**/
	function alphaMode(capabilities:gpu.GpuSurfaceCapabilities):gpu.AlphaMode {
		if (transparent)
			for (wanted in [gpu.AlphaMode.PreMultiplied, gpu.AlphaMode.PostMultiplied])
				for (i in 0...capabilities.alphaModeCount())
					if (capabilities.alphaMode(i) == wanted)
						return wanted;
		return capabilities.alphaMode(0);
	}

	/**
		Mailbox where frames are paced on the compositor's frame callback and
		the surface offers it, Fifo otherwise: under Fifo on Wayland the
		compositor's FIFO and commit-timing protocols can hold frames, while
		the frame callback alone paces Mailbox to the display.
		`ASHUI_PRESENT_MODE=fifo|fifo-relaxed|mailbox|immediate` overrides it;
		one the surface lacks fails at configure.
	**/
	function presentMode(capabilities:gpu.GpuSurfaceCapabilities):gpu.PresentMode {
		switch Sys.getEnv("ASHUI_PRESENT_MODE") {
			case "fifo": return Fifo;
			case "fifo-relaxed": return FifoRelaxed;
			case "mailbox": return Mailbox;
			case "immediate": return Immediate;
			case _:
		}
		if (paceOnRedraw)
			for (i in 0...capabilities.presentModeCount())
				if (capabilities.presentMode(i) == Mailbox)
					return Mailbox;
		return Fifo;
	}

	/** A format without sRGB encoding: the theme's colours are already in sRGB and blend as they are. **/
	function chooseFormat():TextureFormat {
		var capabilities = surface.capabilities(adapter);
		for (wanted in [TextureFormat.Bgra8unorm, TextureFormat.Rgba8unorm])
			for (i in 0...capabilities.formatCount())
				if (capabilities.format(i) == wanted)
					return wanted;
		return surface.preferredFormat(adapter);
	}

	function close(instance:GpuInstance):Void {
		ashui.core.Work.listen(null);
		scheduler.useRealtime(false);
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
