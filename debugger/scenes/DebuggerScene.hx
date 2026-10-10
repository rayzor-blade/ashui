import ashui.core.render.Snapshot;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;

/**
	The debugger's page captured offscreen, on the newest recording or
	`RECORDING`; `ASHUI_DEBUGGER_TAB`, `_AT` and `_TRACK` pick what it shows.
	From the repository root:
	`ASHUI_HAXE_FLAGS="--class-path debugger/haxe" tools/snapshot/run.sh debugger/scenes/DebuggerScene.hx`
**/
class DebuggerScene {
	static function main() {
		ThemeState.init(DefaultTheme.bundle(), Dark);
		Snapshot.scene("debugger", 1440, 900, () -> Debugger.view(Sys.getEnv("RECORDING"), 1440, 900), ThemeState.get().color(Background).rgb(), 1, 1, 0.5);
	}
}
