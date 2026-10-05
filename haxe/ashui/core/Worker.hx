package ashui.core;

/**
	One background thread for work that would hold up a frame: textures
	compressed, skies built. Jobs run one after another, so their working
	memory does not pile up and they take one core rather than all of
	them; each one's result is handed to its `done` on the main thread, at
	the animation scheduler's next tick.

	```haxe
	Worker.run(() -> Environment.fromHdr(bytes), sky -> environment.set(sky));
	```

	On Ash the thread is a fiber thread; on stock HashLink an OS thread.
**/
class Worker {
	static var queue:Null<sys.thread.Deque<Void->Void>> = null;

	/** Runs `work` on the worker thread, then `done` with what it returned on the main thread. **/
	public static function run<T>(work:Void->T, done:T->Void):Void {
		if (queue == null) {
			queue = new sys.thread.Deque();
			var jobs = queue;
			sys.thread.Thread.create(() -> while (true) jobs.pop(true)());
		}
		queue.add(() -> {
			// A job that throws is reported and skipped; the thread goes on to the next.
			var result = try work() catch (e:haxe.Exception) {
				trace('Worker: ${e.details()}');
				return;
			}
			ashui.animation.AnimationScheduler.main.after(0, () -> done(result));
		});
	}
}
