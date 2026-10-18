package dashboard;

import ashui.icons.Remix;
import ashui.layout.Element;
import ashui.reactive.Computed;
import ashui.types.Style;
import dashboard.Widgets.*;

/** The dock: the pages, one press away. **/
class Dock {
	static final PAGES:Array<{tab:Tab, label:String, icon:ashui.svg.Icon}> = [
		{tab: Navigate, label: "Navigate", icon: Remix.NAVIGATION_FILL},
		{tab: Media, label: "Media", icon: Remix.MUSIC_2_FILL},
		{tab: Vehicle, label: "Vehicle", icon: Remix.CAR_FILL},
		{tab: Charging, label: "Charging", icon: Remix.CHARGING_PILE_2_FILL},
		{tab: Camera, label: "Camera", icon: Remix.CAMERA_FILL},
		{tab: Phone, label: "Phone", icon: Remix.PHONE_FILL},
		{tab: Profile, label: "Profile", icon: Remix.USER_3_FILL},
		{tab: More, label: "More", icon: Remix.MORE_FILL}
	];

	static function item(m:Model, screen:Screen, page:{tab:Tab, label:String, icon:ashui.svg.Icon}):Element {
		var wide = screen.labelled;
		var width = Computed.make(() -> wide.get() ? 80.0 : 46.0);
		var body = <div class="dash-item flex flex-col items-center justify-center" gap={4} width={width} height={58}>
			{icon(page.icon, "size-5")}
			<if {wide.get()}><text class="text-xs font-medium">${page.label}</text></if>
		</div>;
		return flag(press(body, () -> m.tab.set(page.tab)), "on", () -> m.tab.get() == page.tab);
	}

	public static function build(m:Model, screen:Screen):Element {
		var items = [for (i in 0...PAGES.length - 1) item(m, screen, PAGES[i])];
		var more = item(m, screen, PAGES[PAGES.length - 1]);
		var dock = <div class="dash-dock flex flex-row items-center gap-1 p-2">
			{items}
			<div class="dash-sep" width={1} height={30} marginLeft={4} marginRight={4} />
			{more}
		</div>;
		// Eight items, the separator and its margins, the gaps, the padding and the border.
		return dockedBottom(dock, () -> screen.width.get(), () -> 8 * (screen.labelled.get() ? 80 : 46) + 59, 24);
	}
}
