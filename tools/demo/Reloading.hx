import ashui.app.WindowedApp;
import ashui.input.Pointer;
import ashui.layout.Element;
import ashui.ui.Component;
import ashui.ui.Hxx.hxx;
import ashui.ui.View;

/**
	Hot reload in a window. Run it with `reload.sh`, click the counters, then
	edit a template below and save: the window takes the new code and every
	count stays, the board's own and each counter's, those the `<for>` built
	included. Body-only edits reload (text, the expressions already
	there); adding a handler or a `${…}` is refused and the old code keeps
	running.

	With `RELOADING_SCRIPT=1` it adds a fruit and clicks counters itself,
	then prints the counts, and prints them again after each reload.
**/
class Reloading {
	static function main() {
		var scripted = Sys.getEnv("RELOADING_SCRIPT") != null;
		WindowedApp.run({title: "ashui hot reload", width: 560, height: 420, onFrame: scripted ? script() : null}, () -> hxx('<board />'));
	}

	/** Adds a fruit, then clicks one counter a frame. **/
	static function script():(Int, Float) -> Void {
		var clicks = [0, 0, 0, 1, 3, 3];
		var renders = 0;
		return (frame, _) -> {
			var app = WindowedApp.current;
			var board = Board.shown;
			// An idle window presents no frames; ask for the next while there are steps left.
			if (clicks.length > 0 || renders == 0)
				app.invalidate();
			if (frame == 2) {
				board.names = board.names.concat(["Plums"]);
			} else if (frame > 2 && clicks.length > 0) {
				var b = app.tree.getBounds(board.counters[clicks.shift()].node);
				Pointer.move(app.tree, b.x + b.width - 24, b.y + b.height / 2);
				Pointer.press(app.tree);
				Pointer.release(app.tree);
			} else if (clicks.length == 0 && Board.renders > renders) {
				Sys.println('${renders == 0 ? "ready" : "reloaded"} ${board.describe()}');
				Sys.stdout().flush();
				renders = Board.renders;
			}
		};
	}
}

/** A heading, a counter of its own, and one counter per fruit, built by a `<for>`. **/
class Board extends View {
	/** How many times a board has rendered; a reload renders it again. **/
	public static var renders = 0;

	/** The board last rendered. **/
	public static var shown:Board;

	@:state public var names:Array<String> = ["Apples", "Pears"];
	@:state var added:Int = 0;

	/** The counters built under it, in order. **/
	public var counters:Array<Counter> = [];

	function render():Element {
		renders++;
		shown = this;
		counters = [];
		return hxx('
			<div class="flex flex-col p-6 gap-4 bg-background" width={560} height={420}>
				<text class="text-2xl font-bold">Counters</text>
				<text class="text-sm text-text-secondary">Click them, then edit tools/demo/Reloading.hx and save.</text>
				{counter("Everything")}
				<for {n in names}>{counter(n)}</for>
				<div class="self-start px-3 py-2 rounded-md bg-surface border border-border hover:bg-surface-elevated transition-colors" focusable={true}
					onClick={addFruit}>
					<text class="text-sm">Add a fruit</text>
				</div>
			</div>
		');
	}

	function addFruit():Void {
		added++;
		names = names.concat(['Fruit $added']);
	}

	function counter(label:String):Element {
		var c = new Counter({label: label});
		counters.push(c);
		return c;
	}

	public function describe():String
		return [for (c in counters) '${c.props.label}=${c.count}'].join(" ");
}

/** A label, a count and a button adding one to it. **/
class Counter extends Component<{label:String}> {
	@:state public var count:Int = 0;

	function render() '
		<div class="flex flex-row items-center justify-between px-4 py-2 rounded-lg bg-surface border border-border">
			<text class="text-base">${props.label}</text>
			<div class="flex flex-row items-center gap-3">
				<text class="text-lg font-bold">${count}</text>
				<div class="px-3 py-1 rounded-md bg-primary hover:bg-primary-hover transition-colors" focusable={true} onClick={() -> count++}>
					<text class="text-sm text-text-inverse">+1</text>
				</div>
			</div>
		</div>
	';
}
