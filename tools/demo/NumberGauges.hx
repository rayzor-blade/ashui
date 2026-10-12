import ashui.components.Badge;
import ashui.components.Button;
import ashui.components.Card;
import ashui.components.Label;
import ashui.components.NumberGauge;
import ashui.components.NumberInput;
import ashui.components.NumberRangeGauge;
import ashui.components.Size;
import ashui.reactive.Reactive;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;

/**
	Filled numbers and intervals, composed entirely in HXX (git-bug 095fab4).
	tools/demo/run.sh tools/demo/NumberGauges.hx
	tools/snapshot/run.sh tools/demo/NumberGauges.hx
	MOTION=1 tools/snapshot/run.sh tools/demo/NumberGauges.hx
**/
class NumberGauges {
	public static inline var WIDTH = 680;
	public static inline var HEIGHT = 590;

	public static function page():ashui.layout.Element {
		var opacity = signal(64.0), gain = signal(1.25);
		var lower = signal(20.0), upper = signal(75.0);
		return <div width={WIDTH} height={HEIGHT} class="bg-background p-8 flex-col gap-6">
			<div class="flex-row items-center justify-between">
				<div class="flex-col gap-2">
					<text class="text-2xl font-semibold">Numeric controls</text>
					<text class="text-sm text-text-secondary">Drag an edge. Scroll to fine-tune.</text>
				</div>
				<badge variant={Secondary} appearance={Outline}>Interactive</badge>
			</div>
			<card>
				<card-header>
					<card-title>Fill and interval</card-title>
					<card-description>Precise values, with the range visible at a glance.</card-description>
				</card-header>
				<card-content class="flex-col gap-5">
					<div class="flex-row items-center justify-between gap-4">
						<label for="gauge-opacity">Opacity</label>
						<number-gauge id="gauge-opacity" value={opacity} min={0} max={100} format={n -> n + " %"} />
					</div>
					<div class="flex-row items-center justify-between gap-4">
						<label for="gauge-gain">Exposure</label>
						<number-gauge id="gauge-gain" value={gain} min={-2} max={2} step={0.05} format={n -> n + " EV"} />
					</div>
					<div class="flex-row items-center justify-between gap-4">
						<label>Temperature</label>
						<number-range-gauge id="gauge-temperature" lower={lower} upper={upper} min={0} max={100}
							format={(a, b) -> a + " – " + b + " °C"} />
					</div>
				</card-content>
				<card-footer class="flex-row items-center justify-between">
					<text class="text-xs text-text-secondary">Tab to a handle · Arrow keys to step</text>
					<button type="button" size={Sm} variant={Outline} onClick={_ -> { opacity.set(64); gain.set(1.25); lower.set(20); upper.set(75); }}>Reset</button>
				</card-footer>
			</card>
			<div class="flex-col gap-3">
				<text class="text-sm font-semibold">One behavior, three sizes</text>
				<for {size in [Size.Sm, Size.Md, Size.Lg]}>
					<div class="flex-row items-center gap-5">
						<div width={70}><label>${size == Size.Sm ? "Small" : size == Size.Md ? "Medium" : "Large"}</label></div>
						<div width={150}><number-gauge size={size} value={12.5} min={0} max={20} step={0.5} /></div>
						<number-input size={size} value={12.5} min={0} max={20} step={0.5} />
					</div>
				</for>
			</div>
		</div>;
	}

	static function main() {
		var light = Sys.getEnv("SCHEME") == "light";
		ThemeState.init(DefaultTheme.bundle(), light ? Light : Dark);
		#if ashui_window
		ashui.app.WindowedApp.run({title: "Numeric controls", width: WIDTH, height: HEIGHT}, page);
		#else
		if (Sys.getEnv("MOTION") == "1") motion(light);
		else ashui.core.render.Snapshot.scene(light ? "number-gauges-light" : "number-gauges", WIDTH, HEIGHT, page,
			ThemeState.get().color(Background).rgb(), 1, 2);
		#end
	}

	#if !ashui_window
	static function motion(light:Bool):Void {
		var result = ashui.debug.MotionRecorder.record(light ? "number-gauges-light" : "number-gauges", WIDTH, HEIGHT, page, {
			fps: 60, frames: 120, minFrames: 120, scale: 1, settle: 0.5,
			overlay: Sys.getEnv("ASHUI_MOTION") == "overlay", clear: ThemeState.get().color(Background).rgb(),
			before: (frame, tree, root) -> {
				function node(selector:String):ashui.layout.Node
					return new ashui.layout.Node(ashui.css.Css.query(tree, root.node.id, selector)[0]);
				function hover(selector:String) {
					var b = tree.getBounds(node(selector));
					ashui.input.Pointer.move(tree, b.x + b.width / 2, b.y + b.height / 2);
				}
				function move(selector:String, fraction:Float) {
					var input = node(selector), b = tree.getBounds(input), edges = tree.getBox(input);
					var t = tree.getBounds(node(selector + " > .thumb"));
					var start = edges.border[3] + edges.padding[3] + t.width / 2;
					var travel = b.width - edges.border[1] - edges.padding[1] - start - t.width / 2;
					ashui.input.Pointer.move(tree, b.x + start + fraction * travel, b.y + b.height / 2);
				}
				function expect(selector:String, value:Float) {
					var input = ashui.ui.Input.at(tree, node(selector).id);
					if (input.valueAsNumber.get() != value) throw 'Gauge motion: $selector expected $value, got ${input.valueAsNumber.get()}';
				}
				var low = '#gauge-temperature > input[data-endpoint="lower"]';
				var high = '#gauge-temperature > input[data-endpoint="upper"]';
				if (frame == 1) { hover("#gauge-opacity"); ashui.input.Pointer.wheel(tree, 0, 80); }
				if (frame == 2) expect("#gauge-opacity", 66);
				if (frame == 10) { hover("#gauge-opacity > .thumb"); ashui.input.Pointer.press(tree); }
				if (frame >= 11 && frame <= 30) move("#gauge-opacity", 0.66 - 0.44 * (frame - 10) / 20);
				if (frame == 31) { ashui.input.Pointer.release(tree); expect("#gauge-opacity", 22); }
				if (frame == 40) { hover(low + " > .thumb"); ashui.input.Pointer.press(tree); }
				if (frame >= 41 && frame <= 60) move(low, 0.2 + 0.2 * (frame - 40) / 20);
				if (frame == 61) { ashui.input.Pointer.release(tree); expect(low, 40); expect(high, 75); }
				if (frame == 70) { hover(high + " > .thumb"); ashui.input.Pointer.wheel(tree, 0, -200); }
				if (frame == 71) expect(high, 70);
				if (frame == 80) { hover(high + " > .thumb"); ashui.input.Pointer.press(tree); }
				if (frame >= 81 && frame <= 100) move(high, 0.7 + 0.18 * (frame - 80) / 20);
				if (frame == 101) { ashui.input.Pointer.release(tree); expect(high, 88); }
				if (frame == 110) ashui.input.Pointer.leave(tree);
			}
		});
		Sys.println(result.report.split("\n")[0]);
	}
	#end
}
