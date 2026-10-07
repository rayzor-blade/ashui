package ashui.media;

import ashui.components.Button;
import ashui.components.DropdownMenu;
import ashui.components.Slider;
import ashui.layout.Element;
import ashui.reactive.Signal;
import ashui.reactive.Watch;
import ashui.reactive.Owner;
import ashui.ui.Component;
import ashui.ui.Ref;
import ashui.media.Player.PlayerState;

typedef PlaybackControlsProps = {
	player:Player,
	/** Keeps an enclosing video's controls visible while a popup is being used. **/
	?onEngagedChange:Bool->Void,
	?id:String
}

/** Optional controls, also usable next to a video with controls=false or on their own. **/
class PlaybackControls extends Component<PlaybackControlsProps> {
	function render():Element {
		Library.use();
		var player = props.player;
		var play = new Ref<Button>();
		var backward = new Ref<Button>();
		var forward = new Ref<Button>();
		var timeline = new Ref<Slider>();
		var menu = new Ref<DropdownMenuTrigger>();
		var volumeOpen = Signal.make(false);
		var menuOpen = Signal.make(false);
		var progress = Signal.make(0.0);
		new Watch(() -> player.duration.get() > 0 ? player.position.get() / player.duration.get() : 0.0,
			v -> progress.set(Math.max(0, Math.min(1, v))));
		if (props.onEngagedChange != null) {
			new Watch(() -> volumeOpen.get() || menuOpen.get(), props.onEngagedChange);
			Owner.onCleanup(() -> props.onEngagedChange(false));
		}
		var root:Element = <div id={props.id} class="ui-media-controls">
			<div class="ui-media-toolbar">
				<button ref={backward} type="button" variant={Ghost} size={Icon} class="ui-media-backward" disabled={player.duration.get() <= 0 || player.position.get() <= 0}
					onClick={_ -> player.seek(player.position.get() - 10)}>
					<svg viewBox="0 0 24 24" width={18} height={18} fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M5 5v14M19 5 9 12l10 7z" /></svg>
				</button>
				<button ref={play} type="button" variant={Ghost} size={Icon} class="ui-media-play" disabled={player.state.get() == Empty || player.state.get() == Failed || player.state.get() == Closed}
					onClick={_ -> player.toggle()}>
					<if {player.isPlaying()}>
						<svg viewBox="0 0 24 24" width={20} height={20} fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
							<path d="M8 5v14M16 5v14" />
						</svg>
					<else>
						<svg viewBox="0 0 24 24" width={20} height={20} fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
							<path d="M7 4v16l13 -8z" />
						</svg>
					</if>
				</button>
				<button ref={forward} type="button" variant={Ghost} size={Icon} class="ui-media-forward" disabled={player.duration.get() <= 0 || player.position.get() >= player.duration.get()}
					onClick={_ -> player.seek(player.position.get() + 10)}>
					<svg viewBox="0 0 24 24" width={18} height={18} fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M19 5v14M5 5l10 7-10 7z" /></svg>
				</button>
				<slider ref={timeline} class="ui-media-timeline" value={progress} min={0} max={1} step={0.001} disabled={player.duration.get() <= 0}
					onChange={v -> if (player.duration.get() > 0) player.seek(v * player.duration.get())} />
				<div class="ui-media-time">
					<text wrap={false}>${clock(player.position.get())}</text>
					<text wrap={false} class="ui-media-duration">${"/ " + clock(player.duration.get())}</text>
				</div>
				<volume-control player={player} open={volumeOpen} />
				<dropdown-menu open={menuOpen} side="top" class="ui-media-options">
					<dropdown-menu-trigger ref={menu} variant={Ghost} size={Icon}>
						<svg viewBox="0 0 24 24" width={20} height={20} fill="currentColor"><circle cx="4" cy="12" r="1.5" /><circle cx="12" cy="12" r="1.5" /><circle cx="20" cy="12" r="1.5" /></svg>
					</dropdown-menu-trigger>
					<dropdown-menu-content>
						<dropdown-menu-item onSelect={() -> { player.seek(0); player.play(); }}>Play from beginning</dropdown-menu-item>
						<dropdown-menu-item onSelect={() -> player.setLoop(!player.looping.get())}>${player.looping.get() ? "Turn repeat off" : "Repeat playback"}</dropdown-menu-item>
					</dropdown-menu-content>
				</dropdown-menu>
			</div>
			<if {player.error.get() != null}>
				<text class="ui-media-error">${player.error.get()}</text>
			</if>
		</div>;
		ashui.css.Identity.of(play.get().tree, play.get().node.id)
			.bindAttribute("aria-label", ashui.reactive.Computed.make(() -> player.isPlaying() ? "Pause" : "Play"));
		ashui.css.Identity.of(backward.get().tree, backward.get().node.id).setAttribute("aria-label", "Seek backward 10 seconds");
		ashui.css.Identity.of(forward.get().tree, forward.get().node.id).setAttribute("aria-label", "Seek forward 10 seconds");
		ashui.css.Identity.of(timeline.get().tree, timeline.get().node.id).setAttribute("aria-label", "Seek");
		ashui.css.Identity.of(menu.get().tree, menu.get().node.id).setAttribute("aria-label", "Playback options");
		return root;
	}

	public static function clock(seconds:Float):String {
		var value = Std.int(Math.max(0, seconds));
		var hours = Std.int(value / 3600);
		var minutes = Std.int(value / 60) % 60;
		return (hours > 0 ? hours + ":" + StringTools.lpad(Std.string(minutes), "0", 2) : Std.string(minutes))
			+ ":" + StringTools.lpad(Std.string(value % 60), "0", 2);
	}
}
