import ashui.app.WindowedApp;

/**
	The debugger in a window. `run.sh [recording dir]` opens that recording,
	or the newest under `.ashui/snapshots/motion`; the picker in the header
	lists the rest.
**/
class DebuggerApp {
	static function main() {
		var args = Sys.args();
		WindowedApp.run({title: "ashui debugger", width: 1440, height: 900}, () -> Debugger.view(args.length > 0 ? args[0] : null, 1440, 900));
	}
}
