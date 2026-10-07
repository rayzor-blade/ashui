package ashui.media;

import ashui.layout.Element;
import ashui.media.PlaybackProps.PlaybackBinding;
import ashui.ui.Component;

/**
	`<audio src={path} />`: native file playback and optional default controls.
	A supplied player remains caller-owned. With controls=false this renders
	only its HXX children; a custom UI uses the public player and its signals.
	Audio and video share hlavi's file/format support and volume behavior.
**/
class Audio extends Component<PlaybackProps> {
	public var player(default, null):Player;

	function render():Element {
		Library.use();
		player = PlaybackBinding.create(props);
		var root:Element = <div id={props.id} class="ui-media-audio">
			<if {PlaybackBinding.read(props.controls, true)}><playback-controls player={player} /></if>
			${children}
		</div>;
		ashui.css.Identity.of(root.tree, root.node.id).bindAttribute("data-state", ashui.reactive.Computed.make(() -> player.stateName()));
		return root;
	}
}
