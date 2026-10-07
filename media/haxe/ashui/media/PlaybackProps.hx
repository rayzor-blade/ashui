package ashui.media;

import ashui.layout.IntoReactive;
import ashui.reactive.Owner;
import ashui.reactive.Watch;
import ashui.media.Player.PlayerState;

/** Props shared by the video and audio tags. A supplied player remains caller-owned. **/
typedef PlaybackProps = {
	?src:IntoReactive<String>,
	?player:Player,
	?autoplay:IntoReactive<Bool>,
	?loop:IntoReactive<Bool>,
	?muted:IntoReactive<Bool>,
	?volume:IntoReactive<Float>,
	/** Optional caller-owned equalizer; null restores flat playback. **/
	?equalizer:IntoReactive<Null<Equalizer>>,
	/** Standard playback controls, true by default. **/
	?controls:IntoReactive<Bool>,
	?onReady:Player->Void,
	?onEnded:Void->Void,
	?onError:String->Void,
	?id:String
}

/** Shared lifecycle and reactive prop bindings for the two playback components. **/
class PlaybackBinding {
	public static function create(props:PlaybackProps):Player {
		var player = props.player == null ? new Player() : props.player;
		if (props.player == null) Owner.onCleanup(player.close);
		if (props.loop != null) new Watch(() -> read(props.loop, false), player.setLoop);
		if (props.muted != null) new Watch(() -> read(props.muted, false), player.setMuted);
		if (props.volume != null) new Watch(() -> read(props.volume, 1.0), player.setVolume);
		if (props.equalizer != null) new Watch(() -> read(props.equalizer, (null : Null<Equalizer>)), player.setEqualizer);
		if (props.src != null) new Watch(() -> read(props.src, ""), src -> player.load(src, read(props.autoplay, false)));
		if (props.autoplay != null) new Watch(() -> read(props.autoplay, false), playing -> {
			if (playing) player.play(); else player.pause();
		});
		var ready = false;
		new Watch(() -> player.state.get(), state -> {
			if (state == Empty || state == Opening) ready = false;
			if (!ready && (state == Paused || state == Playing || state == Buffering || state == Ended)) {
				ready = true;
				if (props.onReady != null) props.onReady(player);
			}
			if (state == Ended && props.onEnded != null) props.onEnded();
		});
		if (props.onError != null) new Watch(() -> player.error.get(), message -> if (message != null) props.onError(message));
		return player;
	}

	public static function read<T>(value:Null<IntoReactive<T>>, fallback:T):T
		return value == null ? fallback : switch value {
			case Const(v): v;
			case Bound(s): s.get();
			case Derived(c): c.get();
		};
}
