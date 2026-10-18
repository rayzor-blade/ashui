package dashboard;

import ashui.icons.Remix;
import ashui.layout.Element;
import ashui.types.Brush;
import ashui.types.Style;
import dashboard.Tab.Appearance;
import dashboard.Widgets.*;

/**
	The Profile page: who is driving, which sets the climate and the paint they like, and how the dashboard looks, light,
	dark, or whichever the system is in, and in what units.
**/
class ProfileView {
	final m:Model;

	public function new(m:Model)
		this.m = m;

	function card(i:Int):Element {
		var p = Model.PROFILES[i];
		var face = <div class="dash-avatar flex items-center justify-center" width={64} height={64} bg={Brush.solid(p.color)}>
			<text class="text-lg font-semibold">${p.initials}</text></div>;
		var tile = <div class="dash-tile flex flex-col items-center gap-3 p-5" width={190} height={220}>
			{face}
			<text class="text-base font-semibold">${p.name}</text>
			<div flexDirection={Column} gap={2} alignItems={Center}>
				<text class="text-xs ink-3">${p.temperature + "°"}</text>
				<text class="text-xs ink-3">${Paint.ALL[p.paint].name}</text>
			</div>
			<if {m.profile.get() == i}>
				<div class="flex flex-row items-center gap-1 accent">{icon(Remix.CHECK_LINE, "size-4")}<text class="text-xs font-semibold">Driving</text></div>
			</if>
		</div>;
		return flag(press(tile, () -> m.choose(i)), "on", () -> m.profile.get() == i);
	}

	function appearance(a:Appearance):Void {
		m.appearance.set(a);
		#if ashui_window
		ashui.theme.WindowTheme.choose(switch a {
			case Auto: null;
			case Light: ashui.theme.ColorScheme.Light;
			case Dark: ashui.theme.ColorScheme.Dark;
		});
		#end
	}

	public function build():Element {
		var drivers = <div class="dash-glass flex flex-col gap-4 p-6" width={660}>
			<text class="dash-title">Driver</text>
			<div flexDirection={Row} gap={12}>{card(0)}{card(1)}{card(2)}</div>
			<text class="text-xs ink-3">The seat's climate and the car's paint follow whoever is driving.</text>
		</div>;
		var look = <div class="dash-glass flex flex-col gap-4 p-6" width={360}>
			<text class="dash-title">Appearance</text>
			{segments(["Auto", "Light", "Dark"], () -> m.appearance.get().getIndex(), i -> appearance(Appearance.createByIndex(i)))}
			<text class="text-xs ink-3">${m.appearance.get() == Auto ? "Follows the system's light or dark." : "Stays as chosen."}</text>
			<text class="dash-title" paddingTop={8}>Units</text>
			{segments(["Kilometres", "Miles"], () -> m.miles.get() ? 1 : 0, i -> m.miles.set(i == 1))}
		</div>;
		return <div position={Absolute} left={24} right={24} top={78} bottom={100} flexDirection={Row} justifyContent={Justify.Center} alignItems={Center} gap={16}>
			{drivers}{look}
		</div>;
	}
}
