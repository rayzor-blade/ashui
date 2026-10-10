import ashui.components.Badge;
import ashui.components.Button;
import ashui.components.ScrollArea;
import ashui.components.Select;
import ashui.components.Tabs;
import ashui.debugger.FrameView;
import ashui.debugger.MotionTimeline;
import ashui.debugger.Recording;
import ashui.debugger.RecordingControls;
import ashui.debugger.RecordingPlayer;
import ashui.debugger.TreeChanges;
import ashui.reactive.Signal;
import ashui.reactive.Watch;

/**
	The ashui debugger: opens a recording `MotionRecorder` wrote and plays
	it back, its frames beside the timeline of its animations, what changed
	in the tree at each frame, and its report.

	`DebuggerApp` opens it in a window; `scenes/DebuggerScene` captures it.
**/
class Debugger {
	/** The debugger's page at `width` × `height`, on `dir` or the newest recording. **/
	public static function view(dir:Null<String>, width:Int, height:Int):ashui.layout.Element {
		ashui.debugger.Library.use();
		var dirs = Recording.list();
		var first = dir != null ? dir : dirs.length > 0 ? dirs[0] : null;
		if (first != null && dirs.indexOf(first) < 0)
			dirs.unshift(first);
		var player = new RecordingPlayer(first == null ? null : new Recording(first));
		var chosen = Signal.make(first == null ? "" : first);
		new Watch(() -> chosen.get(), dir -> if (dir != "" && (player.recording.get() == null || player.recording.get().dir != dir))
			player.open(new Recording(dir)));
		var tab = Signal.make("timeline");
		// Where it opens: a tab, a time in seconds and a track, for a capture of a given moment.
		if (Sys.getEnv("ASHUI_DEBUGGER_TAB") != null)
			tab.set(Sys.getEnv("ASHUI_DEBUGGER_TAB"));
		if (Sys.getEnv("ASHUI_DEBUGGER_AT") != null)
			player.seek(Std.parseFloat(Sys.getEnv("ASHUI_DEBUGGER_AT")));
		if (Sys.getEnv("ASHUI_DEBUGGER_TRACK") != null)
			player.selected.set(Std.parseInt(Sys.getEnv("ASHUI_DEBUGGER_TRACK")));
		return <div class="flex flex-col gap-3 p-4 bg-background" width={width} height={height}>
				<div class="flex flex-row items-center gap-3">
					<text class="text-lg font-semibold">ashui debugger</text>
					<select value={chosen} width={320}>
						${[for (dir in dirs) <select-item value={dir}>${haxe.io.Path.withoutDirectory(dir)}</select-item>]}
					</select>
					<if {player.recording.get() != null}>
						<badge variant={Secondary}>${player.recording.get().frames.length + " frames"}</badge>
						<badge variant={Secondary}>${player.recording.get().tracks.length + " tracks"}</badge>
						<badge variant={player.recording.get().warnings() > 0 ? Warning : Success}>${player.recording.get().warnings() + " warnings"}</badge>
						<if {player.recording.get().regression != null}>
							<badge variant={StringTools.startsWith(player.recording.get().regression, "regression " + player.recording.get().name + ": 0 ") ? Success : Destructive}>
								${player.recording.get().regression.split("\n")[0]}
							</badge>
						</if>
					</if>
				</div>
				<if {player.recording.get() == null}>
					<text class="text-text-secondary">No recordings yet: record one with MotionRecorder, or pass a recording's directory.</text>
				<else>
					<div class="flex flex-row gap-4 grow min-h-0">
						<div class="flex flex-col gap-2 grow min-w-0" flexBasis={0}>
							<frame-view player={player} />
							<recording-controls player={player} />
						</div>
						<div class="ui-debugger-panel" width={620}>
							<tabs value={tab}>
								<tabs-list>
									<tabs-trigger value="timeline">Timeline</tabs-trigger>
									<tabs-trigger value="tree">Tree</tabs-trigger>
									<tabs-trigger value="report">Report</tabs-trigger>
								</tabs-list>
								<tabs-content value="timeline"><scroll-area><motion-timeline player={player} /></scroll-area></tabs-content>
								<tabs-content value="tree"><scroll-area><tree-changes player={player} /></scroll-area></tabs-content>
								<tabs-content value="report">
									<scroll-area orientation="both">
										<text class="ui-debugger-report">${player.recording.get().report + (player.recording.get().regression == null ? "" : "\n" + player.recording.get().regression)}</text>
									</scroll-area>
								</tabs-content>
							</tabs>
						</div>
					</div>
				</if>
			</div>;
	}
}
