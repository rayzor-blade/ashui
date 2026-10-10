package ashui.debugger;

import ashui.draw.DrawContext;
import ashui.draw.Stroke;
import ashui.layout.Element;
import ashui.reactive.Watch;
import ashui.types.Brush;
import ashui.ui.Canvas;
import ashui.ui.Component;
import ashui.ui.Ref;

typedef FrameViewProps = {
	player:RecordingPlayer,
	?id:String
}

/**
	`<frame-view player={player} />`: the recorded frame at the playhead,
	fitted whole into its box, with the selected track's element outlined
	where it was drawn then. One canvas repaints as the playhead moves, as
	a video surface does, rather than an element per frame.
	CSS: `.ui-debugger-frame`.
**/
class FrameView extends Component<FrameViewProps> {
	function render():Element {
		Library.use();
		var player = props.player;
		var canvas = new Ref<Canvas>();
		var root:Element = <div id={props.id} class="ui-debugger-frame">
			<canvas ref={canvas} class="ui-debugger-surface" draw={ctx -> draw(ctx, player)} />
		</div>;
		new Watch(() -> {
			player.recording.get();
			player.selected.get();
			return player.position.get();
		}, _ -> if (canvas.get() != null) canvas.get().repaint());
		return root;
	}

	static function draw(ctx:DrawContext, player:RecordingPlayer):Void {
		var r = player.recording.get();
		if (r == null || r.frames.length == 0)
			return;
		var bitmap = r.bitmap(player.frame.get());
		var w = r.width > 0 ? r.width : bitmap.width, h = r.height > 0 ? r.height : bitmap.height;
		// Contained: the whole frame, centred, at the largest size that fits.
		var scale = Math.min(ctx.width / w, ctx.height / h);
		var x = (ctx.width - w * scale) / 2, y = (ctx.height - h * scale) / 2;
		ctx.image(bitmap, x, y, w * scale, h * scale);
		var id = player.selected.get();
		var track = Lambda.find(r.tracks, t -> t.id == id);
		var at = track == null ? null : Recording.rectAt(track, player.position.get());
		if (at != null)
			ctx.strokeRect(x + at.x * scale, y + at.y * scale, at.w * scale, at.h * scale, new Stroke(2), Brush.solid(0x4cc9f0));
	}
}
