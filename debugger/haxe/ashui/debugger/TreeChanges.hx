package ashui.debugger;

import ashui.components.Button;
import ashui.layout.Element;
import ashui.ui.Component;

typedef TreeChangesProps = {
	player:RecordingPlayer,
	?id:String
}

/**
	`<tree-changes player={player} />`: what changed in the tree at the
	frame at the playhead, as `tree.txt` lists it: elements added, removed,
	and changed with their box, states and restyled values, each with the
	rule it came from when the recording knew it. The frames that changed
	anything are listed above, to jump to.
	CSS: `.ui-debugger-changes`.
**/
class TreeChanges extends Component<TreeChangesProps> {
	function render():Element {
		Library.use();
		var player = props.player;
		return <div id={props.id} class="ui-debugger-changes">
			<if {player.recording.get() != null}>
				<div class="flex flex-row flex-wrap gap-1">
					<for {frame in changedFrames(player.recording.get())}>
						<button type="button" size={Sm} variant={player.frame.get() == frame ? Secondary : Ghost}
							onClick={_ -> player.seek(player.recording.get().times[frame])}>${Std.string(frame)}</button>
					</for>
				</div>
				<for {line in linesAt(player)}>
					${lineView(line)}
				</for>
			</if>
		</div>;
	}

	static function changedFrames(r:Recording):Array<Int> {
		var out = [for (k in r.changes.keys()) k];
		out.sort((a, b) -> a - b);
		return out;
	}

	static function linesAt(player:RecordingPlayer):Array<String> {
		var lines = player.recording.get().changes.get(player.frame.get());
		return lines == null ? ['Nothing changed at frame ${player.frame.get()}.'] : lines;
	}

	/** A line coloured by what it says: an element added, one removed, or a detail of a change. **/
	static function lineView(line:String):Element {
		return if (StringTools.startsWith(line, "+ "))
			<text wrap={false} class="ui-debugger-change-added">${line}</text>
		else if (StringTools.startsWith(line, "- "))
			<text wrap={false} class="ui-debugger-change-removed">${line}</text>
		else if (StringTools.startsWith(line, " "))
			<text wrap={false} class="ui-debugger-change-detail">${StringTools.trim(line)}</text>
		else
			<text wrap={false}>${line}</text>;
	}
}
