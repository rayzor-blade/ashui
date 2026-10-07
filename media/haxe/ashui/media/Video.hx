package ashui.media;

import ashui.canvaskit.Background2D;
import ashui.canvaskit.CanvasKit;
import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.media.PlaybackProps.PlaybackBinding;
import ashui.media.render.VideoTexture;
import ashui.reactive.Computed;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.reactive.Watch;
import ashui.state.Machine;
import ashui.ui.Component;
import ashui.ui.Ref;

typedef VideoProps = {
	> PlaybackProps,
	?fit:IntoReactive<VideoFit>,
	/** Fade idle controls while playing; pointer movement or keyboard focus reveals them. Defaults to true. **/
	?autoHideControls:IntoReactive<Bool>,
	/** Seconds of inactivity before fading controls. Defaults to 2. **/
	?controlsHideDelay:Float
}

private enum ControlsState {
	Shown;
	Waiting(activity:Int);
	Hidden;
}

private enum ControlsEvent {
	Activity;
	Leave;
	Idle;
}

/**
	`<video src={path} />`: native audio/video playback through CanvasKit.
	`controls={false}` leaves the video surface and any supplied HXX children;
	use `player={controller}` to build custom controls around its signals.
	CSS: `.ui-media-video`, `.ui-media-surface`, `.ui-media-controls`.
**/
class Video extends Component<VideoProps> {
	public var player(default, null):Player;
	public var controlsVisible(default, null):Computed<Bool>;

	function render():Element {
		Library.use();
		player = PlaybackBinding.create(props);
		var canvas = new Ref<CanvasKit>();
		var controls = new Ref<PlaybackControls>();
		var popupOpen = Signal.make(false);
		var held = false;
		var activity = 0;
		var machine = new Machine<ControlsState, ControlsEvent>(Shown, (state, event) -> {
			var hide = player.isPlaying() && PlaybackBinding.read(props.autoHideControls, true) && !held;
			return switch [state, event] {
				case [_, Activity]: hide ? Waiting(++activity) : Shown;
				case [_, Leave]: hide ? Hidden : Shown;
				case [Waiting(_), Idle]: hide ? Hidden : Shown;
				case _: null;
			};
		});
		machine.after(Waiting(0), props.controlsHideDelay == null ? 2 : Math.max(0, props.controlsHideDelay), Idle);
		controlsVisible = Computed.make(() -> machine.state.get() != Hidden);
		var texture = new VideoTexture(player);
		Owner.onCleanup(texture.dispose);
		var root:Element = <div id={props.id} class="ui-media-video"
			onPointerEnter={_ -> machine.send(Activity)} onPointerMove={_ -> machine.send(Activity)} onPointerLeave={_ -> machine.send(Leave)}>
			<canvas-kit ref={canvas} class="ui-media-surface" interactive={false} background={new Background2D(None)}
				paint={frame -> texture.paint(frame, PlaybackBinding.read(props.fit, VideoFit.Contain))} />
			<if {PlaybackBinding.read(props.controls, true)}><playback-controls ref={controls} player={player} onEngagedChange={popupOpen.set} /></if>
			${children}
		</div>;
		new Watch(() -> player.frameVersion.get(), _ -> if (canvas.get() != null) canvas.get().repaint());
		new Watch(() -> PlaybackBinding.read(props.fit, VideoFit.Contain), _ -> if (canvas.get() != null) canvas.get().repaint());
		new Watch(() -> player.isPlaying() && PlaybackBinding.read(props.autoHideControls, true), _ -> machine.send(Activity));
		var interaction = ashui.input.Interaction.of(root.node);
		new Watch(() -> {
			var within = interaction.focusWithin.get();
			var focused = ashui.input.Focus.of(root.tree);
			return popupOpen.get() || (within && focused != null && focused.focusVisible.get());
		}, value -> { held = value; machine.send(Activity); });
		new Watch(() -> { visible: controlsVisible.get(), controls: controls.get() }, value -> {
			if (value.controls != null) {
				root.tree.setPassThrough(value.controls.node.id, !value.visible);
				ashui.css.Identity.of(value.controls.tree, value.controls.node.id).setAttribute("aria-hidden", value.visible ? null : "true");
			}
		});
		ashui.css.Identity.of(root.tree, root.node.id).bindAttribute("data-state", ashui.reactive.Computed.make(() -> player.stateName()));
		ashui.css.Identity.of(root.tree, root.node.id).bindAttribute("data-controls", Computed.make(() -> controlsVisible.get() ? "visible" : "hidden"));
		return root;
	}
}
