package ashui.state;

import ashui.animation.AnimationScheduler;
import ashui.reactive.Computed;
import ashui.reactive.Owner;
import ashui.reactive.Signal;

/**
	A reactive finite state machine for transient UI states, such as a tooltip
	waiting to open or an overlay closing.

	The transition function maps a state and event to the next state.
	Return null or the current state to ignore the event. Enum switches let
	the compiler check transition cases:

	```haxe
	enum Tip { Closed; Waiting; Open; Closing; }
	enum TipEvent { Enter; Leave; Timeout; Gone; }

	var tip = new Machine<Tip, TipEvent>(Closed, (s, e) -> switch [s, e] {
	    case [Closed, Enter]: Waiting;
	    case [Waiting, Timeout]: Open;
	    case [Waiting, Leave]: Closed;
	    case [Open, Leave]: Closing;
	    case [Closing, Gone]: Closed;
	    case _: null;
	});
	tip.after(Waiting, 0.5, Timeout);
	tip.after(Closing, 0.12, Gone);
	tip.onEnter(Open, show);
	```

	The state is a signal that UI bindings can track. `name` exposes it for
	`data-state` attributes. Each transition runs exit actions, then entry
	actions, then starts the new state's timers. Leaving a state cancels its
	timers. Events sent by actions are processed after the current transition.

	Actions and timers match enum constructors, so `Loading` also matches
	`Loading(progress)`. Disposing the current owner cancels timers and stops
	the machine from accepting events.
**/
class Machine<S:EnumValue, E> {
	/** The state it is in. **/
	public final state:Signal<S>;

	final transition:(S, E) -> Null<S>;
	final scheduler:AnimationScheduler;
	final enters = new Map<Int, Array<S->Void>>();
	final exits = new Map<Int, Array<S->Void>>();
	final delays = new Map<Int, Array<{seconds:Float, event:E}>>();
	var timers:Array<ashui.animation.AnimationScheduler.Timer> = [];
	var queue:Array<E> = [];
	var moving = false;
	var disposed = false;

	public function new(initial:S, transition:(S, E) -> Null<S>, ?scheduler:AnimationScheduler) {
		state = Signal.make(initial);
		this.transition = transition;
		this.scheduler = scheduler != null ? scheduler : AnimationScheduler.main;
		if (Owner.current != null)
			Owner.onCleanup(dispose);
	}

	/** Takes `event`: moves to the state the transition gives, if any other. **/
	public function send(event:E):Void {
		if (disposed)
			return;
		queue.push(event);
		if (moving)
			return;
		moving = true;
		while (queue.length > 0) {
			var e = queue.shift();
			var from = state.get();
			var to = transition(from, e);
			if (to != null && !Type.enumEq(to, from))
				move(from, to);
		}
		moving = false;
	}

	function move(from:S, to:S):Void {
		for (t in timers)
			t.cancel();
		timers = [];
		var left = exits.get(Type.enumIndex(from));
		if (left != null)
			for (f in left)
				f(from);
		state.set(to);
		var entered = enters.get(Type.enumIndex(to));
		if (entered != null)
			for (f in entered)
				f(to);
		enterTimers(to);
	}

	function enterTimers(to:S):Void {
		var later = delays.get(Type.enumIndex(to));
		// An entry action may have moved it on already.
		if (later != null && Type.enumEq(state.get(), to))
			for (d in later) {
				var event = d.event;
				timers.push(scheduler.after(d.seconds, () -> send(event)));
			}
	}

	/** Runs the initial state's entry actions and starts its timers. Call once after configuring the machine. **/
	public function start():Machine<S, E> {
		var s = state.get();
		var entered = enters.get(Type.enumIndex(s));
		if (entered != null)
			for (f in entered)
				f(s);
		enterTimers(s);
		return this;
	}

	/** Calls `action` each time it enters a state of `kind`'s constructor, with the state. **/
	public function onEnter(kind:S, action:S->Void):Machine<S, E> {
		add(enters, kind, action);
		return this;
	}

	/** Calls `action` each time it leaves a state of `kind`'s constructor, with the state left. **/
	public function onExit(kind:S, action:S->Void):Machine<S, E> {
		add(exits, kind, action);
		return this;
	}

	/**
		Sends `event` after `seconds` in a state matching `kind`'s constructor. Leaving the state cancels the timer.
	**/
	public function after(kind:S, seconds:Float, event:E):Machine<S, E> {
		var list = delays.get(Type.enumIndex(kind));
		if (list == null)
			delays.set(Type.enumIndex(kind), list = []);
		list.push({seconds: seconds, event: event});
		return this;
	}

	/** Whether it is in a state of `kind`'s constructor now; read inside a computed, it follows the state. **/
	public function is(kind:S):Bool
		return Type.enumIndex(state.get()) == Type.enumIndex(kind);

	/**
		Returns the current state constructor name in kebab case, such as `Waiting` → `waiting`, for CSS attributes.
	**/
	public function name():Computed<Null<String>>
		return Computed.make(() -> (kebab(Type.enumConstructor(state.get())) : Null<String>));

	/** Cancels its timers; it takes no more events. **/
	public function dispose():Void {
		disposed = true;
		for (t in timers)
			t.cancel();
		timers = [];
		queue = [];
	}

	static function add<F>(map:Map<Int, Array<F>>, kind:EnumValue, f:F):Void {
		var list = map.get(Type.enumIndex(kind));
		if (list == null)
			map.set(Type.enumIndex(kind), list = []);
		list.push(f);
	}

	static function kebab(name:String):String
		return ~/([a-z0-9])([A-Z])/g.replace(name, "$1-$2").toLowerCase();
}
