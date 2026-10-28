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
import window.TouchPhase;

/**
	Runs a windowed UI. Pass window settings and a root-element builder:

	```haxe
	WindowedApp.run({title: "ashui", width: 640, height: 480}, page);
	```

	Draws when the tree, theme, window size or scale changes. Color-scheme
	transitions keep drawing until settled. Otherwise the loop waits for
	window events. The theme follows the window's appearance.
	Pointer, wheel, keyboard and text events are dispatched through
	`ashui.input.Pointer` and `ashui.input.Keyboard`.
**/
class WindowedApp {
	/** The UI context identifies the window being dispatched. **/
	static final local = new ashui.core.UiContext.Local<Null<WindowedApp>>(() -> null);

	/** The window whose UI or callback is running. */
	public static var current(get, never):Null<WindowedApp>;

	static function get_current()
		return local.value;

	static var manager:Null<WindowManager>;
	public static final windowRevision = ashui.reactive.Signal.make(0);

	public final context:ashui.core.UiContext;

	final config:WindowConfig.WindowConfigData;
	var disposeRoot:Null<Void->Void>;
	var imeWatch:ashui.reactive.Watch<Null<ashui.input.WindowState.CaretArea>>;
	var log:Null<ashui.debug.InputLog>;
	var presented = 0.0;

	public var disposed(default, null) = false;

	/** Queues a window; it is built on the UI thread after the current turn. */
	public static function open(settings:WindowConfig, build:Void->Element):Void {
		if (manager == null)
			throw "WindowedApp.open requires a running application";
		manager.enqueue(settings, build);
	}

	/** A snapshot of open windows, including those which requested close this turn. */
	public static function windows():Array<WindowedApp>
		return manager == null ? [] : manager.windows.copy();

	public final window:Window;
	public final device:GpuDevice;

	/** What draws the tree into the window's frames. **/
	public var offscreen(default, null):Offscreen;

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
	var pendingWheelPhase:Null<TouchPhase> = null;
	var modifiers:window.Modifiers = ashui.input.Events.InputEvent.NO_MODIFIERS;

	/** `ASHUI_FRAME_LOG=<file>` writes each frame's phase timings and each wheel delta there; off when unset, safe either way. **/
	final frameLog:Null<sys.io.FileOutput> = {
		var path = Sys.getEnv("ASHUI_FRAME_LOG");
		if (path != null && windows().length > 0)
			path += "." + windows().length;
		path != null
		&& path != "" ? sys.io.File.write(path, false) : null;
	};

	/** `ASHUI_FRAME_STATS=1` prints two lines a second: the frames drawn, the time between them and each one's drawing, the waits for a redraw that ran out and the layers of the last frame; and the loop's turns, the time they took, the pointer hooks there are and the events that woke it; off when unset, safe either way. **/
	final frameStats = Sys.getEnv("ASHUI_FRAME_STATS") == "1";

	var statSince = 0.0;
	var statFrames = 0;
	var statGap = 0.0;
	var statGapMax = 0.0;
	var statDraw = 0.0;
	var statDrawMax = 0.0;
	var statStalls = 0;

	/** What the loop did in the second: its turns, the time they took, those with something animating, and the events that woke it. **/
	var unsettled = 0;

	static inline var UNSETTLED_TURNS = 90;

	var loopSince = 0.0;

	var loopTurns = 0;
	var loopBusy = 0.0;
	var loopTurnStart = 0.0;
	var loopAnimating = 0;
	var loopTimers = 0;
	var loopEvents = new Map<String, Int>();

	/** `ASHUI_WINDOW_SECONDS=<n>` closes the window after that many seconds, for benches and scripted runs; off when unset. **/
	final closeAfter:Float = {
		var s = Std.parseFloat(Sys.getEnv("ASHUI_WINDOW_SECONDS"));
		Math.isNaN(s)
		|| s <= 0 ? 0.0 : s;
	};

	/** `ASHUI_INPUT_LOG=<path>` records the window's input and writes it to the path when the loop ends (see `ashui.debug.InputLog`). **/
	final inputLog:Null<String> = Sys.getEnv("ASHUI_INPUT_LOG");

	/** `ASHUI_MOTION=overlay` draws motion trails over the frames, `stream` also writes each burst of motion out for review (see `ashui.debug.MotionStream`). **/
	var motion:Null<ashui.debug.MotionStream> = null;

	/** hlwindow's platform code for Wayland. **/
	static inline var WAYLAND = 4;

	/** hlwindow's platform code for a page's canvas, whose redraws are the browser's animation frames. **/
	static inline var WEB_CANVAS = 7;

	/** How long a frame waits for the redraw after the last before drawing anyway, in seconds: a compositor or a browser sends none to a window it does not show. **/
	static inline var FRAME_WAIT_LIMIT = 1.0;

	/** When the surface last gave no frame to draw into. **/
	var refusedAt = Math.NEGATIVE_INFINITY;

	/** How long after the surface gives no frame the next is asked for, in seconds. **/
	static inline var RETRY_FRAME = 0.016;

	/** Whether the last turn's animation ticks changed nothing drawn. **/
	var idleTicks = false;

	/** Whether the last turn drew a frame. **/
	var drewLast = false;

	/**
		How much smaller than the window's own size the layout is drawn: the root's `--ui-zoom`, which a stylesheet sets, under
		`@media` rules that see the window's own size. A zoom of 0.8 lays the UI out in 1.25 times as many units, drawn at the window's
		own resolution, as a browser zoomed out is; text and shapes stay sharp, and pointer input follows.
	**/
	public var zoom(default, null) = 1.0;

	/** `ASHUI_ZOOM=<n>` uses that zoom whatever the stylesheet says, for scripted runs and benches that need a known layout; off when unset, safe either way. **/
	final zoomOverride:Null<Float> = {
		var z = Std.parseFloat(Sys.getEnv("ASHUI_ZOOM"));
		Math.isNaN(z)
		|| z <= 0 ? null : z;
	};

	/** The smallest and largest zoom taken from the stylesheet. **/
	static inline var MIN_ZOOM = 0.25;

	static inline var MAX_ZOOM = 4.0;

	/** Device pixels to a layout unit: the window's scale, and the zoom. **/
	inline function scale():Float
		return window.scaleFactor() * zoom;

	/** How long the loop waits between animation ticks that change nothing drawn, in seconds. **/
	static inline var IDLE_STEP = 0.05;

	/** The longest step animations advance by in one tick, in seconds. **/
	static inline var MAX_STEP = 0.05;

	/** Layout units a wheel scrolls by for each line it reports. **/
	static inline var WHEEL_LINE = 40.0;

	/** Runs `build`'s UI in a window until it closes or `quit` is called. Returns the frames presented. **/
	public static function run(settings:WindowConfig, build:Void->Element):Int {
		if (manager != null)
			throw "Use WindowedApp.open to add a window to the running application";
		var host = new WindowManager();
		manager = host;
		try {
			var frames = host.run(settings, build);
			manager = null;
			return frames;
		} catch (e:haxe.Exception) {
			manager = null;
			throw e;
		}
	}

	function new(window:Window, adapter:GpuAdapter, device:GpuDevice, surface:GpuSurface, config:WindowConfig.WindowConfigData) {
		this.context = ashui.core.UiContext.current;
		this.config = config;
		local.value = this;
		this.window = window;
		this.transparent = config.transparent == true;
		this.adapter = adapter;
		this.device = device;
		this.surface = surface;
		format = chooseFormat();
		offscreen = new Offscreen(device, format);
		// A window keeps running through a GPU error in a frame: it is reported once on stderr.
		offscreen.strictErrors = false;
		motion = ashui.debug.MotionStream.fromEnvironment(offscreen);
		tree = new LayoutTree();
		ashui.input.Cursor.bind(tree, code -> {
			window.setCursorVisible(code != ashui.input.Cursor.HIDDEN);
			if (code != ashui.input.Cursor.HIDDEN)
				window.setCursorIcon(ashui.input.Cursor.icon(code));
		});
		paceOnRedraw = window.platform() == WAYLAND || window.platform() == WEB_CANVAS;
	}

	/** Closes the window after the frame being drawn. **/
	public function quit():Void {
		context.run(requestClose);
	}

	/**
		Closes the window after the frame being drawn, without asking `onClose`: for an app that has asked its own question, such as
		Save, Don't save or Cancel, and has its answer.
	**/
	public function close():Void {
		context.run(() -> {
			if (disposed || quitting)
				return;
			quitting = true;
			ashui.core.Work.notify();
		});
	}

	function requestClose():Void {
		if (disposed || quitting)
			return;
		if (config.onClose != null && !config.onClose())
			return;
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
		// In the window's own logical pixels, as setPosition is, which a layout unit is `zoom` of; the window's position reads in physical ones.
		var factor = window.scaleFactor(), z = zoom;
		var startX = window.x() / factor, startY = window.y() / factor;
		var fromX = startX + press.x * z, fromY = startY + press.y * z;
		var follow:Null<LayoutTree->Void> = null;
		follow = t -> if (t == tree) {
			var at = ashui.input.Pointer.at(tree);
			if (!at.pressed) {
				ashui.input.Pointer.hooks.remove(follow);
				return;
			}
			var x = window.x() / factor + at.x * z,
				y = window.y() / factor + at.y * z;
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
		return Math.round(window.width() / scale());

	public function logicalHeight():Int
		return Math.round(window.height() / scale());

	/** Takes the zoom the stylesheet sets for the window's own size, which `@media` rules read, not the zoomed layout's: the zoom cannot flip with what it makes. **/
	function syncZoom():Void {
		var factor = window.scaleFactor();
		var width = Math.round(window.width() / factor),
			height = Math.round(window.height() / factor);
		offscreen.mediaWidth = width;
		offscreen.mediaHeight = height;
		ashui.css.Css.setViewport(width, height);
		ashui.css.Css.update();
		var text = ashui.css.Css.computed(ashui.css.Identity.of(tree, root.node.id), "--ui-zoom");
		var next = text == null ? 1.0 : Std.parseFloat(text);
		if (zoomOverride != null)
			next = zoomOverride;
		next = Math.isNaN(next) ? 1.0 : Math.max(MIN_ZOOM, Math.min(MAX_ZOOM, next));
		if (next != zoom) {
			zoom = next;
			dirty = true;
		}
	}

	function initialize(build:Void->Element):Void {
		var theme = ThemeState.get();
		// The window's own scheme first, before there is a scheduler, so it applies at once rather than as a transition.
		WindowTheme.follow(window);
		theme.setScheduler(scheduler);
		ThemeState.setRedrawCallback(invalidate);
		ashui.input.WindowState.active.set(window.hasFocus());
		log = inputLog != null && inputLog != "" ? ashui.debug.InputLog.start() : null;
		// The input method is on while text has focus, its candidates by the caret.
		imeWatch = new ashui.reactive.Watch(() -> ashui.input.WindowState.textCaret.get(), area -> {
			var on = area != null;
			if (on != imeOn) {
				imeOn = on;
				window.setImeAllowed(on);
			}
			if (area != null)
				window.setImeCursorArea(area.x * zoom, area.y * zoom, area.width * zoom, area.height * zoom);
		},
			(a, b) -> a == b || (a != null && b != null && a.x == b.x && a.y == b.y && a.width == b.width && a.height == b.height));
		configure();
		root = Owner.root(tree, dispose -> {
			disposeRoot = dispose;
			return build();
		});
		opened = haxe.Timer.stamp();
		presented = opened;
		if (frameLog != null)
			frameLog.writeString("frame\tat_ms\tsince_last_frame\twait\tevents\tn_events\ttick\tflush\tdraw_flush\tlayout\tlist\tgpu\tpresent\tprimitives\n");
	}

	function delay(now:Float, animating:Bool):Float {
		if (closeAfter > 0 && now >= opened + closeAfter) {
			quit();
			return 0;
		}
		if (awaitingFrame && now - awaitingSince > FRAME_WAIT_LIMIT) {
			awaitingFrame = false;
			statStalls++;
		}
		var visible = ashui.input.WindowState.visible.get();
		if (dirty && visible && !awaitingFrame && now - refusedAt >= RETRY_FRAME)
			return 0;
		var timeout = awaitingFrame ? FRAME_WAIT_LIMIT - (now - awaitingSince) : animating ? (idleTicks ? IDLE_STEP : drewLast ? 0.0 : 1 / 120) : Math.POSITIVE_INFINITY;
		if (dirty && visible && now - refusedAt < RETRY_FRAME)
			timeout = Math.min(timeout, RETRY_FRAME - (now - refusedAt));
		if (closeAfter > 0)
			timeout = Math.min(timeout, opened + closeAfter - now);
		return Math.max(0, timeout);
	}

	function turn(event:window.Event, t0:Float, t1:Float, animating:Bool):Void {
		var theme = ThemeState.get();

		var handled = 0;
		var polling = 0.0;
		var kinds = frameLog != null ? new Map<String, Int>() : null;
		while (event != None) {
			if (kinds != null) {
				var k = Type.enumConstructor(event);
				kinds.set(k, (kinds.exists(k) ? kinds.get(k) : 0) + 1);
			}
			if (frameStats) {
				var k = Type.enumConstructor(event);
				loopEvents.set(k, (loopEvents.exists(k) ? loopEvents.get(k) : 0) + 1);
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
		if (offscreen.inspector != null && offscreen.inspector.pointerChanged(tree))
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

		// A frame is drawn for what changed: the theme, the motion overlay, or what the tree's flush reports below.
		// A ticker that changed nothing drawn, an animation out of view, draws nothing.
		if (theme.tick() || (motion != null && (motion.busy() || motion.overlay.shown().length > 0)))
			dirty = true;
		if (awaitingFrame && dirty) {
			coalescePointer();
			return;
		}
		var t2 = haxe.Timer.stamp();
		ashui.core.Work.settle();
		drewLast = false;
		var changed = tree.flush();
		idleTicks = animating && !changed && !dirty;
		if (changed)
			dirty = true;
		// A tree that changes on every turn with no input and nothing animating does not settle, as when a size is made from a measure
		// of itself and the two swap places; said once, since the app then draws a frame each turn.
		if (changed && handled == 0 && !animating)
			unsettled++;
		else
			unsettled = 0;
		if (unsettled == UNSETTLED_TURNS)
			Sys.stderr()
				.writeString('[ashui] the layout has changed on each of $UNSETTLED_TURNS turns with no input and nothing animating: something is sized from a measure of itself\n');
		var t3 = haxe.Timer.stamp();
		// A hidden window draws nothing; what changes waits for it to show again.
		if (dirty && !quitting && ashui.input.WindowState.visible.get() && haxe.Timer.stamp() - refusedAt >= RETRY_FRAME) {
			dirty = false;
			if (draw()) {
				drewLast = true;
				// Hit-test the new layout, including a still pointer. Hover
				// changes can require another frame after this one.
				if (ashui.input.Pointer.refresh(tree))
					dirty = true;
				frames++;
				ashui.core.Memory.afterFrame();
				#if wasm
				// What the web page waits for before it shows the window: the first frame is on the GPU.
				if (frames == 1)
					Sys.println("ashui: ready");
				#end
				var t4 = haxe.Timer.stamp();
				if (frameStats) {
					var gap = t4 - presented, drew = t4 - t3;
					statFrames++;
					statGap += gap;
					statGapMax = Math.max(statGapMax, gap);
					statDraw += drew;
					statDrawMax = Math.max(statDrawMax, drew);
					if (statSince == 0)
						statSince = t4;
					else if (t4 - statSince >= 1) {
						inline function ms(s:Float)
							return Std.string(Math.round(s * 10000) / 10);
						Sys.println('[frames] ${statFrames} in ${ms(t4 - statSince)} ms at ${scale()}x: between ${ms(statGap / statFrames)} ms, at most ${ms(statGapMax)}; drawing ${ms(statDraw / statFrames)} ms, at most ${ms(statDrawMax)}; redraw waits that ran out ${statStalls}; ${offscreen.layerRecords} layers');
						statSince = t4;
						statFrames = 0;
						statGap = statGapMax = statDraw = statDrawMax = 0;
						statStalls = 0;
					}
				}
				if (frameLog != null) {
					var o = offscreen.timings;
					inline function ms(s:Float)
						return Std.string(Math.round(s * 10000) / 10);
					frameLog.writeString([
						Std.string(frames),
						ms(t4 - opened),
						ms(t4 - presented),
						ms(t1 - t0),
						ms(now - t1),
						Std.string(handled),
						ms(t2 - now),
						ms(t3 - t2),
						ms(o.flush),
						ms(o.layout),
						ms(o.list),
						ms(o.draw),
						ms(t4 - t3 - o.flush - o.layout - o.list - o.draw),
						Std.string(offscreen.primitives)
					].join("\t") + "\n");
					frameLog.flush();
				}
				presented = t4;
				if (motion != null)
					motion.frame(tree, root, logicalWidth(), logicalHeight());
				if (config.onFrame != null) {
					config.onFrame(frames, haxe.Timer.stamp() - opened);
					// git-bug 364d4b2: callback writes happen after this frame's
					// flush. Apply them before sleeping, including a canvas resume.
					if (tree.flush())
						dirty = true;
				}
			}
		}
		coalescePointer();
		if (frameStats) {
			loopTurns++;
			loopBusy += haxe.Timer.stamp() - t1;
			if (animating)
				loopAnimating++;
			if (loopSince == 0)
				loopSince = now;
			else if (now - loopSince >= 1) {
				Sys.println('[loop] ${loopTurns} turns in ${Math.round((now - loopSince) * 1000)} ms, busy ${Math.round(loopBusy * 1000)} ms, ${loopAnimating} with something animating, ${loopTimers} woken by a timer, ${ashui.input.Pointer.hooks.length} pointer hooks; state: dirty=$dirty visible=${ashui.input.WindowState.visible.get()} awaiting=$awaitingFrame ${awaitingFrame ? Math.round((now - awaitingSince) * 1000) + " ms" : ""} refused ${refusedAt == Math.NEGATIVE_INFINITY ? "never" : Math.round((now - refusedAt) * 1000) + " ms ago"}; events: ${[for (k => n in loopEvents) k + "=" + n].join(" ")}');
				loopSince = now;
				loopTurns = loopAnimating = loopTimers = 0;
				loopBusy = 0;
				loopEvents.clear();
			}
		}
	}

	/** Applies the batch's last pointer position, then its summed wheel delta. **/
	function applyPointer(readCursor = true):Void {
		// Quiet native moves stay out of the event queue. Consume the latest
		// position and clear the filter before input or application work.
		if (readCursor)
			switch window.takeCursorMove() {
				case CursorMoved(x, y, _):
					var s = scale();
					pendingMove = {x: x / s, y: y / s};
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
			ashui.input.Pointer.wheel(tree, dx, dy, pendingWheelPhase);
			pendingWheelPhase = null;
		}
	}

	function coalescePointer():Void {
		var region = ashui.input.Pointer.quietRegion(tree);
		if (region == null) {
			window.coalesceCursorMoves(0, 0, 0, 0);
			return;
		}
		var s = scale();
		window.coalesceCursorMoves(Math.max(0, region.left * s), Math.max(0, region.top * s), Math.min(window.width(), region.right * s),
			Math.min(window.height(), region.bottom * s));
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
			case Closed:
				quit();
			case Destroyed:
				quitting = true;
			case Resized(_, _) | ScaleFactorChanged(_):
				configure();
				dirty = true;
			case ThemeChanged(_):
				WindowTheme.handle(event);
			case Focused(on):
				if (on)
					ApplicationMenu.focus();
				if (!on)
					ashui.input.Pointer.wheel(tree, 0, 0, TouchPhase.Cancelled);
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
				// Keep already queued wheel input at its original pointer position (095fab4).
				if (pendingWheel)
					applyPointer(false);
				var s = scale();
				pendingMove = {x: x / s, y: y / s};
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
				// Coalesce only deltas within the same phase. Start/end boundaries
				// reach the dispatcher intact, including zero-delta end events (095fab4).
				if (pendingWheel && pendingWheelPhase != phase)
					applyPointer();
				pendingWheel = true;
				pendingWheelPhase = phase;
				switch delta {
					case LineDelta(x, y):
						pendingWheelX += x * WHEEL_LINE;
						pendingWheelY += y * WHEEL_LINE;
					case PixelDelta(x, y):
						var s = scale();
						pendingWheelX += x / s;
						pendingWheelY += y / s;
				}
				if (phase != TouchPhase.Moved)
					applyPointer();
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
		syncZoom();
		offscreen.scale = scale();
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
		capabilities.destroy();
		// Event-driven UI needs one queued frame, not an extra full Retina
		// swapchain image and another frame of input latency (0973e0c).
		configuration.desiredMaximumFrameLatency(1);
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
			case "fifo":
				return Fifo;
			case "fifo-relaxed":
				return FifoRelaxed;
			case "mailbox":
				return Mailbox;
			case "immediate":
				return Immediate;
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

	/** Releases the window's tree, renderer and watches once it is closed. **/
	function teardown():Void {
		if (disposed)
			return;
		disposed = true;
		if (disposeRoot != null) {
			disposeRoot();
			disposeRoot = null;
		}
		if (imeWatch != null) {
			imeWatch.stop();
			imeWatch = null;
		}
		if (frameLog != null)
			frameLog.close();
		if (log != null) {
			log.stop();
			log.save(inputLog + (WindowedApp.windows().length > 1 ? "." + Std.string(window) : ""));
			log = null;
		}
		ThemeState.setRedrawCallback(null);
		ThemeState.get().setScheduler(null);
		tree.dispose();
		root = null;
		offscreen = null;
		config.onFrame = null;
		config.onClose = null;
		surface.destroy();
		window.close();
		local.value = null;
		scheduler.disposeContext(context);
		context.clear();
	}
}

/** One platform loop and device; each window owns its surface and presentation. */
@:access(ashui.app.WindowedApp)
private class WindowManager {
	public final windows:Array<WindowedApp> = [];

	final pending:Array<{settings:WindowConfig, build:Void->Element}> = [];
	final base = ashui.core.UiContext.current;
	#if target.threaded
	final requestsLock = new sys.thread.Mutex();
	#end

	function locked<T>(fn:Void->T):T {
		#if target.threaded
		requestsLock.acquire();
		try {
			var result = fn();
			requestsLock.release();
			return result;
		} catch (error:haxe.Exception) {
			requestsLock.release();
			throw error;
		}
		#else
		return fn();
		#end
	}

	function hasPending():Bool
		return locked(() -> pending.length > 0);

	final scheduler = AnimationScheduler.main;
	final instance:GpuInstance;
	final adapter:GpuAdapter;
	final device:GpuDevice;

	public function new() {
		instance = new GpuInstance();
		// Resolve the device before opening the first platform window.
		adapter = instance.requestAdapter(Power.HighPerformance).await();
		device = ashui.core.render.Renderer.requestDevice(adapter);
	}

	public function enqueue(settings:WindowConfig, build:Void->Element):Void {
		locked(() -> pending.push({settings: settings, build: build}));
		ashui.core.Work.notify();
	}

	function create(settings:WindowConfig, build:Void->Element):WindowedApp {
		return new ashui.core.UiContext(base).run(() -> {
			var config = settings.data;
			if (config.theme != null || ThemeState.tryGet() == null)
				ThemeState.init(config.theme != null ? config.theme : ashui.theme.themes.DefaultTheme.bundle(), Platform.detectSystemColorScheme());
			// Adopt the application stylesheets into this window's cascade.
			ashui.css.Css.update();
			@:privateAccess ashui.css.Css.changed();
			var window = Window.open(settings.attributes());
			if (!window.valid())
				throw "the window could not be opened";
			if (config.active != false)
				window.focus();
			var surface = instance.surface(window.platform(), window.raw(0), window.raw(1), window.raw(2), window.raw(3));
			if (!surface.valid()) {
				window.close();
				throw 'platform ${window.platform()} gave no GPU surface';
			}
			var app = new WindowedApp(window, adapter, device, surface, config);
			windows.push(app);
			WindowedApp.windowRevision.set(WindowedApp.windowRevision.get() + 1);
			try
				app.initialize(build)
			catch (error:haxe.Exception) {
				app.teardown();
				windows.remove(app);
				WindowedApp.windowRevision.set(WindowedApp.windowRevision.get() + 1);
				throw error;
			}
			return app;
		});
	}

	public function run(settings:WindowConfig, build:Void->Element):Int {
		Window.listenDeviceEvents(Never);
		ashui.core.Work.listen(() -> {
			Window.wake();
		});
		scheduler.useRealtime(true);
		var first:WindowedApp = null;
		try {
			first = create(settings, build);
			var last = haxe.Timer.stamp();
			while (windows.length > 0 || hasPending()) {
				// A builder may request another window; drain only the current batch.
				var requests = locked(() -> pending.splice(0, pending.length));
				for (request in requests)
					try
						create(request.settings, request.build)
					catch (error:haxe.Exception) {
						Sys.stderr().writeString("ashui: could not open a window: " + error.details() + "\n");
					}
				for (app in windows.copy())
					if (app.quitting) {
						app.context.run(app.close);
						windows.remove(app);
						WindowedApp.windowRevision.set(WindowedApp.windowRevision.get() + 1);
					}
				if (windows.length == 0)
					continue;
				var t0 = haxe.Timer.stamp(), timeout = Math.POSITIVE_INFINITY;
				var animating = scheduler.hasActive();
				for (app in windows)
					timeout = Math.min(timeout, app.context.run(() -> app.delay(t0, animating)));
				var timer = scheduler.untilNextTimer();
				if (timer != null)
					timeout = Math.min(timeout, timer);
				if (ashui.core.Work.end() || hasPending())
					timeout = 0;
				#if ashui_hot_reload
				timeout = Math.min(timeout, 0.1);
				#end
				var firstApp = windows[0];
				var event = firstApp.window.wait(timeout == Math.POSITIVE_INFINITY ? -1 : timeout);
				ashui.core.Work.begin();
				@:privateAccess ApplicationMenu.pump();
				@:privateAccess FileDialog.pump();
				var now = haxe.Timer.stamp();
				var step = Math.min(now - last, 0.05), elapsed = now - last;
				for (app in windows)
					if (app.motion != null && app.motion.busy()) {
						step = app.motion.step(step);
						elapsed = step;
						break;
					}
				scheduler.tick(step, elapsed);
				last = now;
				for (app in windows)
					app.context.run(() -> {
						var e = app == firstApp ? event : app.window.poll();
						if (timer != null && now - t0 >= timer - 0.001)
							app.loopTimers++;
						app.turn(e, t0, now, animating);
					});
			}
		} catch (e:haxe.Exception) {
			shutdown();
			throw e;
		}
		shutdown();
		return first.frames;
	}

	function shutdown():Void {
		for (app in windows.copy())
			app.context.run(app.close);
		windows.resize(0);
		pending.resize(0);
		ashui.core.Work.listen(null);
		scheduler.useRealtime(false);
		@:privateAccess ApplicationMenu.shutdown();
		device.destroy();
		adapter.destroy();
		instance.destroy();
	}
}
#end
