package dashboard;

import ashui.components.Slider;
import ashui.components.ToggleSwitch;
import ashui.icons.Remix;
import ashui.layout.Element;
import ashui.reactive.Signal;
import ashui.types.Style;
import dashboard.Widgets.*;

/**
	The More page: the screen's brightness and the sounds, what may interrupt, and what the dashboard is made of.
**/
class MoreView {
	final m:Model;

	public function new(m:Model)
		this.m = m;

	function setting(label:String, detail:String, state:Signal<Bool>):Element
		return <div class="flex flex-row items-center justify-between" height={48}>
			<div flexDirection={Column} gap={2}>
				<text class="text-sm font-medium">${label}</text>
				<text class="text-xs ink-3">${detail}</text>
			</div>
			<toggle-switch checked={state} />
		</div>;

	function runtime():String {
		#if wasm
		return "Ash on WebAssembly, drawn by WebGPU";
		#else
		return "Ash, drawn by WebGPU";
		#end
	}

	public function build():Element {
		var brightness = <slider value={m.brightness} min={10} max={100} step={1} onChange={v -> m.brightness.set(v)} />;
		var preferences = <div class="dash-glass flex flex-col gap-3 p-6" width={420}>
			<text class="dash-title">Display and sound</text>
			<div flexDirection={Column} gap={4}>
				<div flexDirection={Row} justifyContent={Justify.SpaceBetween}>
					<text class="text-sm font-medium">Brightness</text>
					<text class="text-sm ink-2">${Math.round(m.brightness.get()) + "%"}</text>
				</div>
				{brightness}
			</div>
			{setting("Sound effects", "Chimes and key clicks", m.sound)}
			{setting("Notifications", "Messages and reminders on the island", m.notifications)}
			{setting("Quiet hours", "Hold notifications from 10 PM to 7 AM", m.quiet)}
		</div>;
		var about = <div class="dash-glass flex flex-col gap-3 p-6" width={360}>
			<text class="dash-title">About</text>
			<div class="flex flex-row items-center gap-3">
				<div class="dash-chip-icon flex items-center justify-center" width={40} height={40}>{icon(Remix.CAR_LINE, "size-5")}</div>
				<div flexDirection={Column} gap={2}>
					<text class="text-sm font-semibold">Ash Drive</text>
					<text class="text-xs ink-3">An ashui demo</text>
				</div>
			</div>
			<text class="text-sm ink-2">Every page here is made of ashui's own parts: signals that change what is shown, a stylesheet, a 3D scene, a canvas and real audio. Nothing in it is a video.</text>
			<text class="text-xs ink-3">${runtime()}</text>
			<text class="text-xs ink-3">Music: Night Drive by Ash Drive; Lofi Fusion by Seth_Makes_Sounds and Cosmic Dark Synthwave by Projecteur, both CC0 from Freesound.</text>
		</div>;
		return <div position={Absolute} left={24} right={24} top={78} bottom={100} flexDirection={Row} justifyContent={Justify.Center} alignItems={Center} gap={16}>
			{preferences}{about}
		</div>;
	}
}
