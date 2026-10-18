package dashboard;

import ashui.icons.Remix;
import ashui.layout.Element;
import ashui.reactive.Computed;
import ashui.types.Brush;
import ashui.types.Style;
import dashboard.Phone.Contact;
import dashboard.Widgets.*;

/**
	The Phone page: a keypad and the number keyed, a call that rings and then runs with its clock, and the people the car
	knows and the calls made. It places no real calls; `Phone` only plays one.
**/
class PhoneView {
	static final KEYS = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["*", "0", "#"]];

	final phone:Phone;

	public function new(phone:Phone)
		this.phone = phone;

	function digit(k:String):Element {
		var cap = <div class="dash-tile flex items-center justify-center" width={84} height={56}><text class="text-xl font-medium">${k}</text></div>;
		return press(cap, () -> phone.key(k));
	}

	function keyRow(keys:Array<String>):Element {
		var caps = [for (k in keys) digit(k)];
		return <div flexDirection={Row} gap={8}>{caps}</div>;
	}

	function keypad():Element {
		var rows = [for (r in KEYS) keyRow(r)];
		return <div class="flex flex-col gap-2">{rows}</div>;
	}

	function status():String
		return switch phone.call.get() {
			case 1: "Calling…";
			case 2: Phone.timer(phone.seconds.get());
			case _: phone.number.get() == "" ? "Key a number" : phone.lookup(phone.number.get()) != null ? phone.number.get() : "Ready to call";
		}

	function callKey():Element {
		function hang()
			return press(<div class="dash-danger flex flex-row items-center justify-center gap-2" height={48}>{icon(Remix.PHONE_FILL, "size-4")}<text class="text-sm font-semibold">End call</text></div>,
			() -> phone.hangUp());
		function call()
			return press(<div class="dash-go flex flex-row items-center justify-center gap-2" height={48}>{icon(Remix.PHONE_FILL, "size-4")}<text class="text-sm font-semibold">Call</text></div>,
			() -> phone.dial(""));
		return <div flexDirection={Column}>
			<if {phone.call.get() != 0}>{hang()}</if>
			<if {phone.call.get() == 0}>{call()}</if>
		</div>;
	}

	function toggle(label:String, ic:ashui.svg.Icon, state:ashui.reactive.Signal<Bool>):Element
		return flag(press(<div class="dash-tile flex flex-col items-center justify-center gap-1" width={100} height={60}>{icon(ic, "size-5")}
			<text class="text-xs font-medium">${label}</text></div>, () -> state.set(!state.get())), "on", () -> state.get());

	function dialler():Element {
		var shown = <text class="dash-big">${live(() -> phone.who())}</text>;
		var line = <text class="text-sm ink-2">${live(() -> status())}</text>;
		function erase()
			return press(<div class="dash-chip flex items-center justify-center" width={40} height={40}>{icon(Remix.DELETE_BACK_2_LINE, "size-4")}</div>, () -> phone.erase());
		return <div class="dash-glass flex flex-col gap-4 p-6" width={330} height={560}>
			<div flexDirection={Row} justifyContent={Justify.SpaceBetween} alignItems={Center}>
				<div flexDirection={Column} gap={2}>{shown}{line}</div>
				<if {phone.call.get() == 0 && phone.number.get() != ""}>{erase()}</if>
			</div>
			<if {phone.call.get() == 0}>{keypad()}</if>
			<if {phone.call.get() != 0}>
				<div flexDirection={Row} gap={8} justifyContent={Justify.Center} paddingTop={16}>
					{toggle("Mute", Remix.MIC_OFF_LINE, phone.muted)}{toggle("Speaker", Remix.VOLUME_UP_LINE, phone.speaker)}
				</div>
			</if>
			<div flexGrow={1} />
			{callKey()}
		</div>;
	}

	function person(c:Contact):Element {
		var face = <div class="dash-avatar flex items-center justify-center" width={40} height={40} bg={Brush.solid(c.color)}>
			<text class="text-sm font-semibold">${c.name.substr(0, 1)}</text></div>;
		var row = <div class="dash-tile flex flex-row items-center gap-3 px-3" height={60}>
			{face}
			<div flexDirection={Column} gap={2} flexGrow={1}>
				<text class="text-sm font-semibold">${c.name}</text>
				<text class="text-xs ink-3">${c.number}</text>
			</div>
			<div class="dash-chip-icon flex items-center justify-center" width={36} height={36}>{icon(Remix.PHONE_FILL, "size-4")}</div>
		</div>;
		return press(row, () -> phone.dial(c.name));
	}

	public function build():Element {
		var people = <div class="dash-glass flex flex-col gap-3 p-6" width={360} height={560}>
			<text class="dash-title">Contacts</text>
			{[for (c in Phone.CONTACTS) person(c)]}
		</div>;
		var recents = <div class="dash-glass flex flex-col gap-3 p-6" width={300} height={560}>
			<text class="dash-title">Recent</text>
			<for {r in phone.recents.get()}>
				<div class="flex flex-row items-center gap-3" height={36}>
					<div class="ink-3">{icon(Remix.HISTORY_LINE, "size-4")}</div>
					<text class="text-sm">${r}</text>
				</div>
			</for>
		</div>;
		return <div position={Absolute} left={24} right={24} top={78} bottom={100} flexDirection={Row} justifyContent={Justify.Center} alignItems={Center} gap={16}>
			{dialler()}{people}{recents}
		</div>;
	}
}
