package ashui.theme;

/**
	Follows the system's light or dark mode: checks it every interval on a
	thread of its own and switches the installed theme's scheme when it
	changes. The first check only records the scheme.
**/
class SystemSchemeWatcher {
	public static inline var DEFAULT_POLL_INTERVAL = 1.0;

	var stopped = false;
	var finished = false;

	function new() {}

	/** A watcher checking once a second. **/
	public static function start():SystemSchemeWatcher {
		return startWithInterval(DEFAULT_POLL_INTERVAL);
	}

	/** Checks every `seconds`. **/
	public static function startWithInterval(seconds:Float):SystemSchemeWatcher {
		var watcher = new SystemSchemeWatcher();
		#if target.threaded
		sys.thread.Thread.create(() -> watcher.loop(seconds));
		#else
		watcher.finished = true;
		#end
		return watcher;
	}

	function loop(seconds:Float):Void {
		var last:Null<ColorScheme> = null;
		while (!stopped) {
			var current = Platform.detectSystemColorScheme();
			if (last != null && last != current) {
				var state = ThemeState.tryGet();
				if (state != null)
					state.setScheme(current);
			}
			last = current;
			Sys.sleep(seconds);
		}
		finished = true;
	}

	/** Stops checking; safe to call more than once. **/
	public function stop():Void {
		stopped = true;
	}

	/** Whether it is still checking. **/
	public function isRunning():Bool {
		return !stopped && !finished;
	}
}

/** Whether and how often to follow the system scheme. **/
@:structInit
class WatcherConfig {
	public var pollInterval:Float = SystemSchemeWatcher.DEFAULT_POLL_INTERVAL;
	public var autoStart:Bool = true;

	public function new(?pollInterval:Float, ?autoStart:Bool) {
		if (pollInterval != null)
			this.pollInterval = pollInterval;
		if (autoStart != null)
			this.autoStart = autoStart;
	}

	/** A started watcher, or null when `autoStart` is off. **/
	public function build():Null<SystemSchemeWatcher> {
		return autoStart ? SystemSchemeWatcher.startWithInterval(pollInterval) : null;
	}
}
