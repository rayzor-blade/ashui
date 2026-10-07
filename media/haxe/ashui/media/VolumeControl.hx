package ashui.media;

import ashui.components.Button;
import ashui.components.Popover;
import ashui.components.Slider;
import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.reactive.Computed;
import ashui.reactive.Signal;
import ashui.reactive.Watch;
import ashui.ui.Component;
import ashui.ui.Ref;

typedef VolumeControlProps = {
	player:Player,
	/** Optional controlled popover state. **/
	?open:IntoReactive<Bool>,
	?onOpenChange:Bool->Void,
	?id:String
}

/** An icon trigger opens a compact volume slider and a mute icon button. **/
class VolumeControl extends Component<VolumeControlProps> {
	function render():Element {
		Library.use();
		var player = props.player;
		var loudness = Signal.make(player.volume.get());
		var mute = new Ref<Button>();
		var trigger = new Ref<PopoverTrigger>();
		new Watch(() -> player.volume.get(), loudness.set);
		var root:Element = <popover id={props.id} open={props.open} onOpenChange={props.onOpenChange} side="top" class="ui-media-volume-control">
			<popover-trigger ref={trigger} variant={Ghost} size={Icon} class="ui-media-volume-trigger">
				${speaker(player)}
			</popover-trigger>
			<popover-content>
				<div class="ui-media-volume-panel">
					<button ref={mute} type="button" variant={Ghost} size={Icon} class="ui-media-mute" onClick={_ -> player.setMuted(!player.muted.get())}>${speaker(player)}</button>
					<slider value={loudness} min={0} max={1} step={0.01} width={112} onChange={v -> {
						player.setVolume(v);
						if (v > 0) player.setMuted(false);
					}} />
					<text class="ui-media-volume-level">${(player.muted.get() ? 0 : Math.round(player.volume.get() * 100)) + "%"}</text>
				</div>
			</popover-content>
		</popover>;
		identity(mute.get()).bindAttribute("aria-label", Computed.make(() -> player.muted.get() ? "Unmute" : "Mute"));
		identity(trigger.get()).bindAttribute("aria-label", Computed.make(() -> player.muted.get() ? "Volume: muted" : "Volume: " + Math.round(player.volume.get() * 100) + "%"));
		return root;
	}

	static function speaker(player:Player):Element
		return <if {player.muted.get() || player.volume.get() == 0}>
			<svg viewBox="0 0 24 24" width={20} height={20} fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
				<path d="M11 5 6 9H3v6h3l5 4zM16 9l5 6m0-6-5 6" />
			</svg>
		<else>
			<if {player.volume.get() > 0.5}>
				<svg viewBox="0 0 24 24" width={20} height={20} fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
					<path d="M11 5 6 9H3v6h3l5 4zM15 8a5 5 0 0 1 0 8M18 5a9 9 0 0 1 0 14" />
				</svg>
			<else>
				<svg viewBox="0 0 24 24" width={20} height={20} fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
					<path d="M11 5 6 9H3v6h3l5 4zM15 8a5 5 0 0 1 0 8" />
				</svg>
			</if>
		</if>;

	static function identity(element:Element):ashui.css.Identity
		return ashui.css.Identity.of(element.tree, element.node.id);
}
