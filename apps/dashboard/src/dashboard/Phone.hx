package dashboard;

import ashui.animation.AnimationScheduler;
import ashui.reactive.Signal;

typedef Contact = {name:String, number:String, color:Int};

/**
	The phone paired with the car: a number being dialled, a call, and the calls made. A call rings for two seconds, is
	answered, and runs until it is ended, its clock ticking; nobody is really called.
**/
class Phone {
	public static final CONTACTS:Array<Contact> = [
		{name: "Grace", number: "020 7946 0132", color: 0x6d8cff},
		{name: "Tobi", number: "020 7946 0871", color: 0xf59e0b},
		{name: "Mum", number: "020 7946 0455", color: 0x22c55e},
		{name: "Work", number: "020 7946 0900", color: 0xa78bfa}
	];

	/** What has been keyed. **/
	public final number = Signal.make("");

	/** 0 nothing, 1 ringing, 2 on the line. **/
	public final call = Signal.make(0);

	public final seconds = Signal.make(0.0);
	public final muted = Signal.make(false);
	public final speaker = Signal.make(true);
	public final recents = Signal.make(["Tobi · missed", "Grace · 12 min", "Work · 3 min"]);

	var ticking = false;
	var ringing = 0.0;

	public function new() {}

	public function key(digit:String):Void {
		if (call.get() == 2) {
			// Keys during a call are tones: shown for a moment, not kept.
			return;
		}
		if (number.get().length < 14)
			number.set(number.get() + digit);
	}

	public function erase():Void {
		var n = number.get();
		if (n.length > 0)
			number.set(n.substr(0, n.length - 1));
	}

	/** The contact whose number, or whose name, `s` is. **/
	public function lookup(s:String):Null<Contact> {
		var plain = StringTools.replace(s, " ", "");
		for (c in CONTACTS)
			if (c.name == s || StringTools.replace(c.number, " ", "") == plain)
				return c;
		return null;
	}

	public function who():String {
		var n = number.get();
		var c = lookup(n);
		return c != null ? c.name : n == "" ? "No number" : n;
	}

	public function dial(s:String):Void {
		if (call.get() != 0)
			return;
		if (s != "")
			number.set(s);
		if (number.get() == "")
			return;
		call.set(1);
		seconds.set(0);
		ringing = 0;
		muted.set(false);
		if (ticking)
			return;
		ticking = true;
		AnimationScheduler.main.addTicker(dt -> {
			if (call.get() == 0) {
				ticking = false;
				return false;
			}
			if (call.get() == 1) {
				ringing += dt;
				if (ringing >= 2)
					call.set(2);
			} else
				seconds.set(seconds.get() + dt);
			true;
		});
	}

	public function hangUp():Void {
		if (call.get() == 0)
			return;
		var line = who() + (call.get() == 2 ? " · " + Math.max(1, Math.round(seconds.get() / 60)) + " min" : " · cancelled");
		recents.set([line].concat(recents.get().slice(0, 4)));
		call.set(0);
		number.set("");
	}

	/** 1:07 for 67 seconds. **/
	public static function timer(seconds:Float):String {
		var s = Std.int(seconds);
		return Std.int(s / 60) + ":" + (s % 60 < 10 ? "0" : "") + (s % 60);
	}
}
