# Sketches

A sketch draws in immediate mode: you describe the picture again every frame, and
keep whatever must last from frame to frame in your own fields. Give one to a
canvas with `sketch`.

```haxe
class Bouncer implements Sketch {
	var x = 40.0;
	var vx = 120.0;

	public function new() {}

	public function setup(ctx:SketchContext):Void {}

	public function draw(ctx:SketchContext, t:Float, dt:Float):Void {
		x += vx * dt;
		if (x < 10 || x > ctx.width - 10)
			vx = -vx;
		var p = ctx.painter();
		p.fill(Brush.solid(0x3b82f6)).circle(x, ctx.height / 2, 10);
	}
}

<canvas width={400} height={200} sketch={new Bouncer()} />
```

`setup` runs once, before the first `draw`. `draw` runs every frame with `t`, the
seconds since the sketch started, and `dt`, the seconds since the last frame, both
on the animation scheduler's clock, so a test or a recording steps a sketch as it
steps animations. A sketch that is out of view is not drawn and its clock waits.

## Input

A canvas with a sketch can take focus, so it gets keys after a click. What the user
did since the previous frame is in `ctx.events`, in order. Every transition is
there, so a click that began and ended between two frames arrives as a
`PointerDown` and a `PointerUp`:

```haxe
for (event in ctx.events)
	switch event {
		case PointerDown(x, y, button, _): start(x, y);
		case PointerMove(x, y, _): if (ctx.mouseIsPressed) drag(x, y);
		case KeyDown(_, physical, repeat, _) if (!repeat): press(physical);
		case Text(text): typed += text;
		case Resize(width, height): relayout(width, height);
		case _:
	}
```

The events are pointer down, up and move, wheel, key down and up (with `repeat`),
text, input-method composition, focus, blur, resize, and touch start, move, end and
cancel. Positions are in the sketch's own coordinates. A press holds the pointer
until the button comes up, so a drag that leaves the canvas keeps arriving.

For a sketch that only needs the latest state: `ctx.mouseX`, `ctx.mouseY`,
`ctx.mouseIsPressed` and `ctx.keyIsDown(physicalKey)`; `ctx.input` has the rest
(`buttons`, `focused`, `touchesDown()`).

## Idle, paused and slow

A sketch is run once for each frame the window draws. To cost less:

- `ctx.unchanged()` in `draw` keeps the last picture and asks for no new frame; the next frame still runs.
- `ctx.rest()` does that and stops running the sketch until the user does something in the canvas, the canvas resizes, or the program calls the canvas's `wake()`. A window with nothing else going on is then left to sleep.
- `fps={30.0}` on the canvas limits it to that many frames a second; `dt` is the time since the last frame drawn.
- `paused={signal}` stops it while true; its clock waits, and the window is not woken for it.

A sketch in a hidden window or out of view is not run either.
