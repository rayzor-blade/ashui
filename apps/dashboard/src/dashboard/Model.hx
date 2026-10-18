package dashboard;

import ashui.animation.AnimationScheduler;
import ashui.reactive.Computed;
import ashui.reactive.Signal;
import dashboard.Tab.Appearance;
import dashboard.Tab.Gear;

/** A place the route and the chargers' list share. **/
typedef Charger = {name:String, detail:String, free:Int, of:Int, kw:Int, km:Float};

/** Someone who drives the car: what the car remembers of them. **/
typedef Profile = {name:String, initials:String, color:Int, temperature:Float, paint:Int};

/**
	What the dashboard knows: the car, its climate, its charge, the phone and who is driving. Every piece is a signal, so
	whatever shows it follows it and whatever changes it only sets it. `step` moves the simulation on, a little each
	frame, while the app runs: the car cruises, the charge rises and a call's clock runs.
**/
class Model {
	public static final CHARGERS:Array<Charger> = [
		{name: "Granary Square", detail: "1.3 km · 150 kW", free: 4, of: 6, kw: 150, km: 1.3},
		{name: "Coal Drops Yard", detail: "1.6 km · 50 kW", free: 1, of: 4, kw: 50, km: 1.6},
		{name: "Pancras Square", detail: "2.1 km · 22 kW", free: 0, of: 2, kw: 22, km: 2.1}
	];

	public static final PROFILES:Array<Profile> = [
		{name: "Amara", initials: "AM", color: 0x6d8cff, temperature: 21.5, paint: 0},
		{name: "Tobi", initials: "TO", color: 0xf59e0b, temperature: 20.0, paint: 3},
		{name: "Guest", initials: "G", color: 0x22c55e, temperature: 22.0, paint: 5}
	];

	// Where the driver is.
	public final tab = Signal.make(Tab.Vehicle);

	// Driving.
	public final gear = Signal.make(Gear.D);
	public final speed = Signal.make(0.0);
	public final trip = Signal.make(38.4);
	public final odometer = Signal.make(12480.0);
	public final locked = Signal.make(true);
	public final paint = Signal.make(0);
	public final miles = Signal.make(false);

	// Climate.
	public final auto = Signal.make(true);
	public final target = Signal.make(21.5);
	public final ac = Signal.make(true);
	public final fan = Signal.make(3);
	public final defrost = Signal.make(false);
	public final guard = Signal.make(true);

	// Charge.
	public final charge = Signal.make(72.0);
	public final limit = Signal.make(80.0);
	public final charging = Signal.make(true);

	// Navigation: the charger being driven to, and whether guidance is on.
	public final destination = Signal.make(0);
	public final guiding = Signal.make(true);
	/** Kilometres driven toward the destination since guidance began. **/
	public final progress = Signal.make(0.0);
	public final zoom = Signal.make(1.0);
	public final search = Signal.make("");

	// Who is driving.
	public final profile = Signal.make(0);
	public final appearance = Signal.make(Appearance.Auto);
	public final brightness = Signal.make(80.0);
	public final notifications = Signal.make(true);
	public final quiet = Signal.make(false);
	public final sound = Signal.make(true);

	// A little of the world.
	/** Seconds, set about fifteen times a second: what moves for show, a ring spreading from a tyre or the sound's bars, follows it. **/
	public final clock = Signal.make(0.0);
	public final minute = Signal.make(0);

	/** The range the charge gives, in kilometres. **/
	public final range:Computed<Float>;

	/** Minutes until the limit, at the charge rate. **/
	public final minutesToLimit:Computed<Float>;

	var elapsed = 0.0;
	var sinceMinute = 0.0;

	public function new() {
		range = Computed.make(() -> charge.get() * 5.72);
		minutesToLimit = Computed.make(() -> charging.get() && charge.get() < limit.get() ? (limit.get() - charge.get()) * 7.0 : 0.0);
		minute.set(wallMinute());
	}

	/** Minutes since midnight, by the wall clock. **/
	static function wallMinute():Int {
		var now = Date.now();
		return now.getHours() * 60 + now.getMinutes();
	}

	/** The time as the island shows it. **/
	public static function clockText(minute:Int):String {
		var h = Std.int(minute / 60) % 24, m = minute % 60;
		return (h % 12 == 0 ? 12 : h % 12) + ":" + (m < 10 ? "0" : "") + m + (h < 12 ? " AM" : " PM");
	}

	public static function greeting(minute:Int):String {
		var h = Std.int(minute / 60) % 24;
		return h < 5 ? "Good night" : h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening";
	}

	/** Speed as shown, in km/h or mph. **/
	public function shown(kmh:Float):Float
		return miles.get() ? kmh * 0.621371 : kmh;

	public function unit():String
		return miles.get() ? "mph" : "km/h";

	public function distance(km:Float):Float
		return miles.get() ? km * 0.621371 : km;

	/** Consumption as shown: kWh to the 100 km, or to the 100 miles. **/
	public function consumption(kwhPer100Km:Float):Float
		return miles.get() ? kwhPer100Km * 1.609344 : kwhPer100Km;

	public function distanceUnit():String
		return miles.get() ? "mi" : "km";

	/** Shifts gear: the car coasts to a stop in park or neutral, and only a stopped car goes into reverse or park. **/
	public function shift(to:Gear):Void {
		if ((to == P || to == R) && speed.get() > 8)
			return;
		gear.set(to);
	}

	public function choose(index:Int):Void {
		var p = PROFILES[index];
		profile.set(index);
		target.set(p.temperature);
		paint.set(p.paint);
	}

	/** Starts guidance to charger `i`. **/
	public function navigateTo(i:Int):Void {
		destination.set(i);
		progress.set(0);
		guiding.set(true);
	}

	/** Kilometres still to go to the destination. **/
	public function remaining():Float
		return Math.max(0, CHARGERS[destination.get()].km - progress.get());

	/** Minutes still to go, at the speed the car does, or at a city's pace when it is stopped. **/
	public function minutesAway():Float
		return remaining() / Math.max(speed.get(), 30) * 60;

	public function setTemperature(value:Float):Void
		target.set(Math.max(16, Math.min(28, Math.round(value * 2) / 2)));

	/** The cruising speed the gear asks for at time `t`. **/
	static function cruising(g:Gear, t:Float):Float
		return switch g {
			case D: 86 + 14 * Math.sin(t * Math.PI * 2 / 6) + 4 * Math.sin(t * Math.PI * 2 / 2);
			case R: 7;
			case _: 0;
		}

	/** Moves the world on by `dt` seconds; called each frame. **/
	public function step(dt:Float):Void {
		// Each frame, so what moves on the pages moves at the rate they are drawn: a step that changes nothing drawn slows the app's loop.
		elapsed += dt;
		clock.set(elapsed);
		var d = dt;
		var s = speed.get(), goal = cruising(gear.get(), elapsed);
		// Pulls toward the goal: harder to stop than to start.
		s += (goal - s) * Math.min(1, d * (goal < s ? 1.6 : 0.9));
		if (Math.abs(goal - s) < 0.05)
			s = goal;
		speed.set(s);
		if (s > 0) {
			trip.set(trip.get() + s * d / 3600);
			odometer.set(odometer.get() + s * d / 3600);
			// What the guidance has the car driven: a slice of the speed, as the route is a few streets of a city.
			if (guiding.get() && gear.get() == D) {
				var left = remaining() - s * d / 3600 * 0.05;
				progress.set(CHARGERS[destination.get()].km - Math.max(0, left));
				if (left <= 0)
					guiding.set(false);
			}
		}
		if (charging.get() && charge.get() < limit.get())
			charge.set(Math.min(limit.get(), charge.get() + d * 0.02));
		else if (charge.get() >= limit.get() && charging.get())
			charging.set(false);
		sinceMinute += dt;
		if (sinceMinute >= 1) {
			sinceMinute = 0;
			var m = wallMinute();
			if (m != minute.get())
				minute.set(m);
		}
	}

	/** Runs `step` each frame, for as long as the app does. **/
	public function run():Void {
		AnimationScheduler.main.addTicker(dt -> {
			step(dt);
			true;
		});
	}
}
