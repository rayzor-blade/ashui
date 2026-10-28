package ashui.media;

import ashui.layout.Element;
import ashui.media.PlaybackProps.PlaybackBinding;
import ashui.ui.Component;

/**
	Plays native audio with optional default controls:
	`<audio src={path} />`.

	Set `controls={false}` to render only the supplied HXX children. Pass a
	player to build custom controls from its signals; the caller owns that player.
	Audio and video share hlavi's format support and volume behavior.
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
