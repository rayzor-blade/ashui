package ashui.debug;

import ashui.layout.LayoutTree;
import ashui.input.InputClock;
import ashui.input.Keyboard;
import ashui.input.Pointer;
import window.Modifiers;
import window.MouseButton;

/** One input as the window gave it to a tree: what `Pointer`, `Keyboard` and the window's focus received. **/
enum InputRecord {
	Move(x:Float, y:Float, modifiers:Null<Modifiers>);
	Leave;
	Press(button:MouseButton);
	Release(button:MouseButton);
	Wheel(dx:Float, dy:Float);
	ModifiersChanged(modifiers:Modifiers);
	Key(event:window.KeyEvent, modifiers:Null<Modifiers>);
	Text(text:String, modifiers:Null<Modifiers>);
	Composition(text:String, cursor:Int);
	WindowFocus(on:Bool);
}

/** An input and when it came, in seconds since its log started. **/
typedef InputEntry = {time:Float, record:InputRecord}

/**
	A recording of the input a tree received: pointer movement, buttons and
	wheel, keys, text, input-method composition and the window's focus,
	each with its time. While no log is started the input code checks one
	null and records nothing.

	A log replays into an offscreen recording: `player` gives the
	`before` step that `Snapshot.sequence` and `MotionRecorder.record` run
	each frame, and it sends each input when the animation clock reaches
	its time. While it plays, `InputClock` reads the same times, so a
	double-click or a select's typeahead is decided as it was recorded.

	```haxe
	var log = InputLog.start();
	// … use the UI …
	log.stop();
	log.save(".ashui/input/session.hxs");
	MotionRecorder.record("session", 800, 600, build, {frames: 300, before: InputLog.load(".ashui/input/session.hxs").player()});
	```

	`WindowedApp` records the window's input to a file when
	`ASHUI_INPUT_LOG` names one.
**/
class InputLog {
	/** The log recording now, if one is. **/
	public static var current(default, null):Null<InputLog> = null;

	public final entries:Array<InputEntry>;
	/** The tree it records; the first that received input. **/
	var tree:Null<LayoutTree> = null;
	final started:Float;

	/** While a log plays, the entry being sent, which `InputClock` reads the time of; nothing records meanwhile. **/
	static var sending:Null<InputEntry> = null;
	static var playing = false;

	function new(?entries:Array<InputEntry>) {
		this.entries = entries != null ? entries : [];
		started = InputClock.now();
	}

	/** Starts recording, ending a log already recording. **/
	public static function start():InputLog {
		if (current != null)
			current.stop();
		return current = new InputLog();
	}

	/** Stops recording. **/
	public function stop():Void {
		if (current == this)
			current = null;
	}

	/** Records `record`, received by `tree`, when a log is recording it. **/
	@:allow(ashui.input)
	@:allow(ashui.app)
	static function note(tree:Null<LayoutTree>, record:InputRecord):Void {
		var log = current;
		if (log == null || playing)
			return;
		if (tree != null) {
			if (log.tree == null)
				log.tree = tree;
			else if (log.tree != tree)
				return;
		}
		log.entries.push({time: InputClock.now() - log.started, record: record});
	}

	/** Writes the log to `path`, making its directory, and beside it a `.txt` of the same name with a line per input, for reading. **/
	public function save(path:String):Void {
		var dir = haxe.io.Path.directory(path);
		if (dir != "" && !sys.FileSystem.exists(dir))
			sys.FileSystem.createDirectory(dir);
		sys.io.File.saveContent(path, haxe.Serializer.run(entries));
		sys.io.File.saveContent(haxe.io.Path.withExtension(path, "txt"), lines());
	}

	/** The log `save` wrote to `path`. **/
	public static function load(path:String):InputLog
		return new InputLog(haxe.Unserializer.run(sys.io.File.getContent(path)));

	/** A line per input: its time in milliseconds and what it was. **/
	public function lines():String
		return [for (e in entries) '${Std.string(Math.round(e.time * 1000))}ms\t${Std.string(e.record)}'].join("\n") + "\n";

	/**
		The step that plays the log into a tree, one call a frame: it sends
		each input whose time the animation clock has reached since its
		first call. From then on `InputClock` reads the log's time: each
		input's own while it is sent, the animation clock's between them.
	**/
	public function player():(Int, LayoutTree, Dynamic) -> Void {
		var next = 0;
		var base:Null<Float> = null;
		var scheduler = ashui.animation.AnimationScheduler.main;
		return (_, tree, _) -> {
			if (base == null) {
				base = scheduler.clock;
				InputClock.source = () -> sending != null ? sending.time : scheduler.clock - base;
			}
			var now = scheduler.clock - base;
			playing = true;
			try {
				while (next < entries.length && entries[next].time <= now + 1e-9) {
					sending = entries[next++];
					send(tree, sending.record);
				}
			} catch (e:haxe.Exception) {
				sending = null;
				playing = false;
				throw e;
			}
			sending = null;
			playing = false;
		}
	}

	/** Sends `record` to `tree` as the window did. **/
	public static function send(tree:LayoutTree, record:InputRecord):Void {
		switch record {
			case Move(x, y, m):
				Pointer.move(tree, x, y, m);
			case Leave:
				Pointer.leave(tree);
			case Press(b):
				Pointer.press(tree, b);
			case Release(b):
				Pointer.release(tree, b);
			case Wheel(dx, dy):
				Pointer.wheel(tree, dx, dy);
			case ModifiersChanged(m):
				Pointer.modifiers(tree, m);
			case Key(e, m):
				Keyboard.input(tree, e, m);
			case Text(t, m):
				Keyboard.text(tree, t, m);
			case Composition(t, c):
				Keyboard.composition(tree, t, c);
			case WindowFocus(on):
				if (ashui.input.WindowState.active.get() != on)
					ashui.input.WindowState.active.set(on);
		}
	}
}
