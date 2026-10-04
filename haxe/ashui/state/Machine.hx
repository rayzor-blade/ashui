package ashui.state;

import ashui.animation.AnimationScheduler;
import ashui.reactive.Computed;
import ashui.reactive.Owner;
import ashui.reactive.Signal;

/**
	A finite state machine on signals, for the transient states a component
	passes through: a tooltip waiting to show, showing and fading; an overlay
	opening, open and closing.

	Its states are an enum, `S`, and so are the events it takes, `E`. The
	transition function says where an event leads from a state, typically a
	`switch` over both, which the compiler checks for cases left out;
	returning null, or the state it is in, leaves it where it is:

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

	Its state is a signal, so a computed, a watch, a bound property or a
	`data-state` attribute (`name`) follows it, as anything follows a
	signal. Actions run as it moves: the state left's exit actions, then
	the state entered's entry actions, then that state's timers start,
	each sending its event after its time on the scheduler's clock unless
	the state is left first. An event an action sends is taken once the
	move is done. States match by constructor, so an action or timer for
	`Loading` covers `Loading(progress)` whatever its arguments.

	It is cleaned up with the owner current when it is made: its timers
	are cancelled and it takes no more events.
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

	/** Runs the entry actions and starts the timers of the state it starts in, as if it had just entered it; once, after they are set. **/
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

	/** Sends `event` `seconds` after it enters a state of `kind`'s constructor, unless it leaves first: a transient state's way on. **/
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

	/** Its state's constructor's name in kebab case, `Waiting` as `waiting`, for a `data-state` attribute that CSS reads. **/
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
