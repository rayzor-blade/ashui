package ashui.media;

import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.state.Machine;
import media.StreamReadStatus;

enum ChannelState {
	Open;
	Backpressured;
	Draining;
	Ended;
	Failed;
	Closed;
}

private enum ChannelEvent {
	Accepted;
	Blocked;
	Finish;
	End;
	Failure;
	Dispose;
}

/**
	A typed native media channel with bounded input and output queues.
	Writes and polls never block for capacity or data. Rejected inputs remain
	caller-owned; accepted inputs are retained natively, so the caller can
	close its handle. Each read transfers ownership of its output to the caller.
	`finish()` drains queued media before EOF; `close()` cancels processing.

	The current owner closes channels on cleanup. Without an owner, the
	caller must close the channel.
**/
class MediaChannel<Input, Output> {
	public final state:Signal<ChannelState>;
	public final error = Signal.make((null : Null<String>));
	public var disposed(default, null) = false;

	final machine:Machine<ChannelState, ChannelEvent>;
	final writeNative:Input->Bool;
	final pollNative:Void->StreamReadStatus;
	final readNative:Void->Output;
	final finishNative:Void->Void;
	final closeNative:Void->Void;
	var released = false;

	function new(write:Input->Bool, poll:Void->StreamReadStatus, read:Void->Output, finish:Void->Void, close:Void->Void) {
		writeNative = write;
		pollNative = poll;
		readNative = read;
		finishNative = finish;
		closeNative = close;
		machine = new Machine<ChannelState, ChannelEvent>(Open, (state, event) -> switch [state, event] {
			case [Closed, _]: null;
			case [_, Dispose]: Closed;
			case [Failed, _] | [Ended, _]: null;
			case [_, Failure]: Failed;
			case [_, End]: Ended;
			case [_, Finish]: Draining;
			case [Open, Blocked] | [Backpressured, Blocked]: Backpressured;
			case [Open, Accepted] | [Backpressured, Accepted]: Open;
			case _: null;
		});
		state = machine.state;
		if (Owner.current != null)
			Owner.onCleanup(this.close);
	}

	/** Attempts a nonblocking write. False means backpressure: keep the input and retry after draining output. **/
	public function tryWrite(value:Input):Bool {
		checkOpen();
		if (state.get() == Draining || state.get() == Ended)
			throw "Media channel input is finished";
		try {
			var accepted = writeNative(value);
			machine.send(accepted ? Accepted : Blocked);
			return accepted;
		} catch (e:Dynamic)
			return fail(e);
	}

	/** Returns `Pending`, `Ready`, or `Ended`. Read a ready output before polling can advance. **/
	public function poll():StreamReadStatus {
		checkOpen();
		try {
			var status = pollNative();
			if (status == StreamReadStatus.Ended)
				machine.send(End);
			return status;
		} catch (e:Dynamic)
			return fail(e);
	}

	/** Transfers one ready output to the caller. The caller must close native frame or chunk handles. **/
	public function read():Output {
		if (poll() != StreamReadStatus.Ready)
			throw "Poll must report Ready before reading media";
		try
			return readNative()
		catch (e:Dynamic)
			return fail(e);
	}

	/** Stops new writes and flushes queued media. Continue reading until `Ended`. **/
	public function finish():Void {
		checkOpen();
		if (state.get() == Draining || state.get() == Ended)
			return;
		try {
			finishNative();
			machine.send(Finish);
		} catch (e:Dynamic)
			fail(e);
	}

	public function close():Void {
		if (disposed)
			return;
		disposed = true;
		machine.send(Dispose);
		machine.dispose();
		release();
	}

	public inline function dispose():Void
		close();

	function checkOpen():Void {
		if (disposed)
			throw "Media channel is closed";
		if (state.get() == Failed)
			throw error.get();
	}

	function fail(e:Dynamic):Dynamic {
		error.set(Std.string(e));
		machine.send(Failure);
		// Preserve the original worker error if releasing it reports another error.
		try
			release()
		catch (_:Dynamic) {}
		throw e;
	}

	function release():Void {
		if (released)
			return;
		released = true;
		closeNative();
	}

	@:allow(ashui.media)
	static function capacity(?limits:MediaLimits):{items:Int, bytes:haxe.Int64} {
		var items = limits == null || limits.maxItems == null ? 8 : limits.maxItems;
		var bytes = limits == null || limits.maxBytes == null ? 16 * 1024 * 1024 : limits.maxBytes;
		if (items < 1 || items > 1024 || bytes < 1 || bytes > 256 * 1024 * 1024)
			throw "Media limits must be 1..1024 items and 1..256 MiB";
		return {items: items, bytes: haxe.Int64.ofInt(bytes)};
	}
}
