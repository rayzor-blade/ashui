package ashui.debugger;

import ashui.debugger.Recording.Track;
import ashui.layout.Element;
import ashui.ui.Component;
import ashui.ui.Div;
import ashui.ui.Ref;

typedef MotionTimelineProps = {
	player:RecordingPlayer,
	?id:String
}

/**
	`<motion-timeline player={player} />`: every animation in the recording
	as a lane: its element and property, then a bar from when it began to
	when it ended, marked when its checks found a problem. The playhead runs
	across the lanes; a click on a lane moves it there and selects the
	track, whose verdict shows below.
	CSS: `.ui-debugger-timeline`, `.ui-debugger-lane`, `.ui-debugger-bar`,
	`[data-issues]`, `[data-selected]`.
**/
class MotionTimeline extends Component<MotionTimelineProps> {
	function render():Element {
		Library.use();
		var player = props.player;
		return <div id={props.id} class="ui-debugger-timeline">
			<if {player.recording.get() == null || player.recording.get().tracks.length == 0}>
				<text class="ui-debugger-empty">No animations were recorded.</text>
			</if>
			<div class="ui-debugger-lanes">
				<for {track in tracksOf(player)}>
					${lane(player, track)}
				</for>
			</div>
			${details(player)}
		</div>;
	}

	static function lane(player:RecordingPlayer, track:Track):Element {
		var span = player.duration.get();
		var start = Math.max(0, track.began);
		var end = track.ended != null ? track.ended : Math.min(span, track.began + track.delay + track.duration);
		var area = new Ref<Div>();
		var row:Element = <div class="ui-debugger-lane" onClick={_ -> player.selected.set(track.id)}>
			<div class="ui-debugger-lane-label">
				<text wrap={false} class="ui-debugger-lane-name">${'#${track.id} ${track.label}'}</text>
				<text wrap={false} class="ui-debugger-lane-property">${track.property}</text>
			</div>
			<div ref={area} class="ui-debugger-lane-area" onPointerDown={e -> {
				var b = area.get().tree.getBounds(area.get().node);
				if (b != null && b.width > 0)
					player.seek((e.x - b.x) / b.width * player.duration.get());
			}}>
				<div class="ui-debugger-gap" flexGrow={start} />
				<div class="ui-debugger-bar" flexGrow={Math.max(end - start, span / 400)} />
				<div class="ui-debugger-gap" flexGrow={Math.max(0, span - end)} />
				<div class="ui-debugger-playhead-row">
					<div class="ui-debugger-gap" flexGrow={player.position.get()} />
					<div class="ui-debugger-playhead" />
					<div class="ui-debugger-gap" flexGrow={Math.max(0, player.duration.get() - player.position.get())} />
				</div>
			</div>
		</div>;
		var identity = ashui.css.Identity.of(row.tree, row.node.id);
		if (track.issues.length > 0)
			identity.setAttribute("data-issues", "true");
		identity.bindAttribute("data-selected", ashui.reactive.Computed.make(() -> player.selected.get() == track.id ? "true" : null));
		return row;
	}

	static function tracksOf(player:RecordingPlayer):Array<Track> {
		var r = player.recording.get();
		return r == null ? [] : r.tracks;
	}

	static function selectedOf(player:RecordingPlayer):Array<Track> {
		var id = player.selected.get();
		return [for (t in tracksOf(player)) if (t.id == id) t];
	}

	/** The selected track's declaration and verdict. **/
	static function details(player:RecordingPlayer):Element {
		return <div class="ui-debugger-details">
			<for {track in selectedOf(player)}>
				<div class="ui-debugger-details-body">
					<text class="ui-debugger-details-title">${'#${track.id} ${track.kind} · ${track.label} · ${track.property}'}</text>
					<text>${'${track.from} → ${track.to}'}</text>
					<text class="ui-debugger-muted">${'began ${RecordingControls.ms(track.began)}, delay ${RecordingControls.ms(track.delay)}, ${RecordingControls.ms(track.duration)} along ${track.curve}; ${track.end}'}</text>
					<for {issue in track.issues}><text class="ui-debugger-issue">${issue}</text></for>
					<for {note in track.notes}><text class="ui-debugger-muted">${note}</text></for>
					<if {track.issues.length == 0}><text class="ui-debugger-ok">Behaved as declared.</text></if>
				</div>
			</for>
		</div>;
	}
}
