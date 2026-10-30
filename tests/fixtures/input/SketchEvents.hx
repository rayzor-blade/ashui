import ashui.draw.Sketch;
import ashui.draw.Sketch.SketchContext;
import ashui.draw.SketchInput.SketchEvent;
import ashui.input.Pointer;
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.ui.Canvas;
import ashui.ui.Div;

private class Recorder implements Sketch {
	public final frames:Array<Array<SketchEvent>> = [];
	public var mouse = [0.0, 0.0];
	public var pressed = false;

	public function new() {}

	public function setup(ctx:SketchContext):Void {}

	public function draw(ctx:SketchContext, t:Float, dt:Float):Void {
		frames.push(ctx.events);
		mouse = [ctx.mouseX, ctx.mouseY];
		pressed = ctx.mouseIsPressed;
	}
}

/** A sketch is given every input event since its last frame, in order, and the polled state as it stands. **/
class SketchEvents {
	static var failures = 0;

	static function check(name:String, ok:Bool, ?detail:Dynamic) {
		Sys.println((ok ? "ok   " : "FAIL ") + name + (ok || detail == null ? "" : " " + detail));
		if (!ok)
			failures++;
	}

	static function names(events:Array<SketchEvent>):String
		return [for (e in events) Type.enumConstructor(e)].join(",");

	static function main() {
		var tree = new LayoutTree();
		var rec = new Recorder();
		var other:Div = null;
		var root:Div = Owner.root(tree, _ -> <div width={400} height={240}>
			<canvas width={200} height={100} sketch={rec} />
			${other = <div width={50} height={50} />}
		</div>);
		function frame(dt = 0.016) {
			tree.flush();
			tree.computeLayout(root.node, 400, 240);
			ashui.animation.AnimationScheduler.main.tick(dt);
		}
		frame();
		frame();
		var first = rec.frames.length;
		check("the sketch draws", first >= 1, first);

		Pointer.move(tree, 20, 30);
		Pointer.press(tree);
		Pointer.release(tree);
		frame();
		var last = rec.frames[rec.frames.length - 1];
		check("a press and release between two frames both arrive, in order", names(last).indexOf("PointerDown,PointerUp") >= 0, names(last));
		check("a move arrives before them", names(last).indexOf("PointerMove") == 0, names(last));
		check("the polled position follows", rec.mouse[0] == 20 && rec.mouse[1] == 30, rec.mouse);
		check("and nothing is held after the release", !rec.pressed);
		frame();
		check("a frame with no input has no events", rec.frames[rec.frames.length - 1].length == 0);

		Pointer.press(tree);
		Pointer.move(tree, 350, 200);
		frame();
		check("a drag that leaves the canvas still reports its moves", names(rec.frames[rec.frames.length - 1]).indexOf("PointerMove") >= 0
			&& rec.pressed && rec.mouse[0] == 350 && rec.mouse[1] == 200, [names(rec.frames[rec.frames.length - 1]), rec.mouse]);
		Pointer.release(tree);

		Pointer.touch(tree, 1, Started, 40, 40);
		Pointer.touch(tree, 1, Moved, 60, 50);
		Pointer.touch(tree, 1, Ended, 60, 50);
		frame();
		check("touches arrive in order", names(rec.frames[rec.frames.length - 1]).indexOf("TouchStart,TouchMove,TouchEnd") >= 0,
			names(rec.frames[rec.frames.length - 1]));
		Sys.println(failures == 0 ? "ALL PASSED" : '$failures FAILED');
		Sys.exit(failures == 0 ? 0 : 1);
	}
}
