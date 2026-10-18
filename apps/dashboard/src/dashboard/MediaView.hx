package dashboard;

import ashui.components.Slider;
import ashui.draw.DrawContext;
import ashui.icons.Remix;
import ashui.layout.Element;
import ashui.reactive.Computed;
import ashui.reactive.Signal;
import ashui.reactive.Watch;
import ashui.types.Brush;
import ashui.types.Style;
import dashboard.Ink.*;
import dashboard.Widgets.*;

/**
	The Media page: what is playing, with its cover, its place in the track, the keys of a player, the volume, and the
	three tracks to pick from. The sound is hlavi's, through ashui's `Player`: on a desktop it plays natively, and in a
	page on an audio element, and either way it is the track's own file that is heard. The bars follow the track, from the
	band levels written when it was composed, to where it has played.
**/
class MediaView {
	final m:Model;
	final music:Music;
	final screen:Screen;

	public function new(m:Model, music:Music, screen:Screen) {
		this.m = m;
		this.music = music;
		this.screen = screen;
	}

	/** Bars for the sound: sixteen, each as loud as its band is. **/
	function bars(width:Float, height:Float):DrawContext->Void
		return ctx -> {
			follow();
			m.clock.get();
			var primary = primary();
			var n = Music.BANDS, gap = 5.0, w = (width - gap * (n - 1)) / n;
			var playing = music.playing();
			var position = music.livePosition();
			for (i in 0...n) {
				var level = playing ? 0.04 + 0.96 * music.level(i, position) : 0.04;
				var h = Math.max(4, level * height);
				ctx.fillRect(i * (w + gap), height - h, w, h, Brush.linear(0, height - h, 0, height).stop(0, primary, 0.95).stop(1, CYAN, 0.55), Math.min(w / 2, 4));
			}
		};

	function key(document:ashui.svg.Icon, act:Void->Void, ?on:Void->Bool):Element {
		var el = <div class="media-key flex items-center justify-center" width={44} height={44}>{icon(document, "size-5")}</div>;
		if (on != null)
			flag(el, "on", on);
		return press(el, act);
	}

	function bigPlay():Element {
		var b = <div class="media-play flex items-center justify-center" width={64} height={64}>
			<if {music.playing()}>{icon(Remix.PAUSE_FILL, "size-7")}</if>
			<if {!music.playing()}>{icon(Remix.PLAY_FILL, "size-7")}</if>
		</div>;
		return press(b, music.toggle);
	}

	function row(i:Int):Element {
		var t = Music.TRACKS[i];
		var line = <div class="media-row flex flex-row items-center gap-3 px-3" height={60}>
			<canvas width={40} height={40} draw={Art.draw(40, t.hue)} />
			<div flexDirection={Column} gap={2} flexGrow={1}>
				<text class="text-sm font-semibold">${t.title}</text>
				<text class="text-xs ink-3">${t.artist + " · " + t.bpm + " BPM"}</text>
			</div>
			<if {music.index.get() == i && music.playing()}><div class="accent">{icon(Remix.VOLUME_UP_LINE, "size-4")}</div></if>
			<text class="text-xs ink-3">${Music.clockText(t.seconds)}</text>
		</div>;
		return flag(press(line, () -> {
			if (music.index.get() == i)
				music.toggle();
			else
				music.select(i, true);
		}), "on", () -> music.index.get() == i);
	}

	public function build():Element {
		// The slider's position is the track's, and a drag of it seeks.
		var fraction = Signal.make(0.0);
		new Watch(() -> {
			var d = music.player.duration.get();
			d > 0 ? music.player.position.get() / d : 0.0;
		}, f -> fraction.set(f));
		var volume = music.volume;
		var progress = <slider value={fraction} min={0} max={1} step={0.001} onChange={f -> music.seekFraction(f)} />;
		var level = <slider value={volume} min={0} max={1} step={0.01} onChange={v -> music.setVolume(v)} />;
		var hue = Computed.make(() -> music.current().hue);
		var art = <canvas width={240} height={240} draw={ctx -> Art.draw(240, hue.get())(ctx)} />;
		var player = <div class="flex flex-col gap-4" width={300}>
			{art}
			<div flexDirection={Column} gap={2}>
				<text class="text-2xl font-semibold">${live(() -> music.current().title)}</text>
				<text class="text-sm ink-2">${live(() -> music.current().artist + " · " + music.current().album)}</text>
			</div>
			<div flexDirection={Column} gap={4}>
				{progress}
				<div flexDirection={Row} justifyContent={Justify.SpaceBetween}>
					<text class="text-xs ink-3">${Music.clockText(music.player.position.get())}</text>
					<text class="text-xs ink-3">${Music.clockText(music.player.duration.get())}</text>
				</div>
			</div>
			<div flexDirection={Row} alignItems={Center} justifyContent={Justify.SpaceBetween}>
				{key(Remix.SHUFFLE_LINE, () -> music.shuffle.set(!music.shuffle.get()), () -> music.shuffle.get())}
				{key(Remix.SKIP_BACK_FILL, () -> music.advance(-1, true))}
				{bigPlay()}
				{key(Remix.SKIP_FORWARD_FILL, () -> music.advance(1, true))}
				{key(Remix.REPEAT_LINE, () -> music.repeat.set(!music.repeat.get()), () -> music.repeat.get())}
			</div>
			<div flexDirection={Row} alignItems={Center} gap={10}>
				<div class="ink-3">{icon(Remix.VOLUME_UP_LINE, "size-4")}</div>
				<div flexGrow={1} flexBasis={0} flexDirection={Column}>{level}</div>
			</div>
		</div>;
		function side()
			return <div class="flex flex-col gap-4" flexGrow={1} flexBasis={0}>
			<div flexDirection={Column} gap={2}>
				<text class="text-xs ink-3">UP NEXT</text>
				{row(0)}{row(1)}{row(2)}
			</div>
			<div flexGrow={1} />
			<canvas width={484} height={120} draw={bars(484, 120)} />
		</div>;
		return <div position={Absolute} left={24} right={24} top={78} bottom={100} flexDirection={Row} justifyContent={Justify.Center} alignItems={Center}>
			<div class="dash-glass flex flex-row gap-8 p-8" width={880}>
				{player}
				<if {screen.width.get() >= 860}>{side()}</if>
			</div>
		</div>;
	}
}
