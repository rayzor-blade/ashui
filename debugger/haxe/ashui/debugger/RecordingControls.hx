package ashui.debugger;

import ashui.components.Button;
import ashui.components.Slider;
import ashui.layout.Element;
import ashui.reactive.Signal;
import ashui.reactive.Watch;
import ashui.ui.Component;
import ashui.ui.Ref;

typedef RecordingControlsProps = {
	player:RecordingPlayer,
	?id:String
}

/**
	`<recording-controls player={player} />`: a recording's transport, as
	`ashui.media`'s playback controls are: a frame back, play or pause, a
	frame on, a scrubber over the whole recording, the time and frame at
	the playhead, and its speed and repeat. Built from `Button` and `Slider`,
	with their keyboard, focus and pointer behaviour.
	CSS: `.ui-debugger-controls`.
**/
class RecordingControls extends Component<RecordingControlsProps> {
	function render():Element {
		Library.use();
		var player = props.player;
		var play = new Ref<Button>(), back = new Ref<Button>(), on = new Ref<Button>(), scrub = new Ref<Slider>();
		var progress = Signal.make(0.0);
		new Watch(() -> player.duration.get() > 0 ? player.position.get() / player.duration.get() : 0.0, v -> progress.set(Math.max(0, Math.min(1, v))));
		var root:Element = <div id={props.id} class="ui-debugger-controls">
			<button ref={back} type="button" variant={Ghost} size={Icon} disabled={player.recording.get() == null || player.frame.get() <= 0}
				onClick={_ -> player.step(-1)}>
				<svg viewBox="0 0 24 24" width={18} height={18} fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M6 5v14M18 5 9 12l9 7z" /></svg>
			</button>
			<button ref={play} type="button" variant={Ghost} size={Icon} disabled={player.recording.get() == null} onClick={_ -> player.toggle()}>
				<if {player.playing.get()}>
					<svg viewBox="0 0 24 24" width={20} height={20} fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M8 5v14M16 5v14" /></svg>
				<else>
					<svg viewBox="0 0 24 24" width={20} height={20} fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M7 4v16l13 -8z" /></svg>
				</if>
			</button>
			<button ref={on} type="button" variant={Ghost} size={Icon}
				disabled={player.recording.get() == null || player.frame.get() >= player.recording.get().frames.length - 1} onClick={_ -> player.step(1)}>
				<svg viewBox="0 0 24 24" width={18} height={18} fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M18 5v14M6 5l9 7-9 7z" /></svg>
			</button>
			<slider ref={scrub} class="ui-debugger-scrubber" value={progress} min={0} max={1} step={0.0005} disabled={player.recording.get() == null}
				onChange={v -> { player.pause(); player.seek(v * player.duration.get()); }} />
			<div class="ui-debugger-time">
				<text wrap={false}>${ms(player.position.get()) + " / " + ms(player.duration.get())}</text>
				<text wrap={false} class="ui-debugger-frame-number">${"frame " + player.frame.get()}</text>
			</div>
			<button type="button" variant={Ghost} size={Sm} class="ui-debugger-rate" onClick={_ -> player.rate.set(next(player.rate.get()))}>
				${player.rate.get() + "×"}
			</button>
			<button type="button" variant={player.looping.get() ? Secondary : Ghost} size={Sm} onClick={_ -> player.looping.set(!player.looping.get())}>Repeat</button>
		</div>;
		label(play.get(), null, player);
		label(back.get(), "Previous frame");
		label(on.get(), "Next frame");
		label(scrub.get(), "Playhead");
		return root;
	}

	static function label(e:Element, text:Null<String>, ?player:RecordingPlayer):Void {
		var identity = ashui.css.Identity.of(e.tree, e.node.id);
		if (player != null)
			identity.bindAttribute("aria-label", ashui.reactive.Computed.make(() -> player.playing.get() ? "Pause" : "Play"));
		else
			identity.setAttribute("aria-label", text);
	}

	/** The speed after `rate`: real time, then slower, then back. **/
	static function next(rate:Float):Float
		return rate >= 1 ? 0.5 : rate >= 0.5 ? 0.25 : rate >= 0.25 ? 0.1 : 1;

	/** Seconds as whole milliseconds. **/
	public static function ms(seconds:Float):String
		return Math.round(seconds * 1000) + "ms";
}
