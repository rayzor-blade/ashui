import ashui.components.NumberGauge;
import ashui.components.NumberInput;
import ashui.components.NumberRangeGauge;
import ashui.components.Size;
import ashui.css.Css;
import ashui.css.Identity;
import ashui.input.Focus;
import ashui.input.Interaction;
import ashui.input.Keyboard;
import ashui.input.Pointer;
import ashui.layout.LayoutTree;
import ashui.layout.Node;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.ui.Div;
import ashui.ui.Form;
import ashui.ui.Ref;

/** Actual input, focus, form and drag lifetime checks for the gauges (095fab4). **/
class NumberGauges {
	static var failures = 0;
	static var checks = 0;
	static function check(name:String, ok:Bool, ?detail:Dynamic):Void {
		checks++;
		Sys.println((ok ? "ok   " : "FAIL ") + name + (ok ? "" : ': $detail'));
		if (!ok) failures++;
	}
	static function key(k:window.Key, code:window.KeyCode):window.KeyEvent
		return Input(Code(code), k, None, Standard, Pressed, false, Unavailable);

	static function variant(size:Size):Void {
		var tree = new LayoutTree(), dispose = () -> {};
		var value = Signal.make(1.25), lower = Signal.make(1.1), upper = Signal.make(1.8);
		var disabled = Signal.make(false), fieldsetDisabled = Signal.make(false);
		var changes = 0, intervals = 0, parentWheels = 0;
		var form = new Ref<Form>(), submitted:FormData = null;
		var root:Div = Owner.root(tree, stop -> {
			dispose = stop;
			return <div width={600} height={300} class="flex-col" onWheel={_ -> parentWheels++}>
				<form ref={form} class="flex-col items-start gap-4" onSubmit={data -> submitted = data}>
					<fieldset disabled={fieldsetDisabled} class="flex-col items-start gap-4">
						<number-gauge id="single" name="gain" width={320} size={size} value={value} min={1.05} max={2.05} step={0.05}
							disabled={disabled} format={v -> v + " EV"} onChange={_ -> changes++} />
						<number-range-gauge id="interval" lowerId="lower" upperId="upper" lowerName="low" upperName="high" width={320} size={size}
							lower={lower} upper={upper} min={1.05} max={2.05} step={0.05} disabled={disabled} onChange={(_, _) -> intervals++} />
					</fieldset>
					<number-input id="number" size={size} value={1.15} min={1.05} max={1.3} step={0.1} />
				</form>
			</div>;
		});
		function settle() for (_ in 0...3) { tree.flush(); tree.computeLayout(root.node, 600, 300); }
		function node(selector:String):Node return new Node(Css.query(tree, root.node.id, selector)[0]);
		function bounds(selector:String) return tree.getBounds(node(selector));
		function hover(selector:String) {
			var b = bounds(selector);
			Pointer.move(tree, b.x + b.width / 2, b.y + b.height / 2);
		}
		function press(selector:String) { hover(selector); Pointer.press(tree); settle(); }
		function moveTo(selector:String, fraction:Float) {
			var b = bounds(selector), t = bounds(selector + " > .thumb"), edge = tree.getBox(node(selector));
			var start = edge.border[3] + edge.padding[3] + t.width / 2;
			var travel = b.width - edge.border[1] - edge.padding[1] - start - t.width / 2;
			Pointer.move(tree, b.x + start + fraction * travel, b.y + b.height / 2);
		}
		settle();
		var expected = size == Sm ? 24 : size == Md ? 32 : 40;
		check('$size gauge dimensions honor explicit width', bounds("#single").width == 320 && bounds("#single").height == expected
			&& bounds("#interval").width == 320 && bounds("#interval").height == expected);
		check('$size flat grips have three dots per endpoint', Css.query(tree, root.node.id, ".ui-number-gauge-grip").length == 3
			&& Css.query(tree, root.node.id, ".ui-number-gauge-dot").length == 9);
		var sb = bounds("#single"), text = bounds("#single > .ui-number-gauge-value > text");
		check('$size formatted number is centered', Math.abs(text.x + text.width / 2 - sb.x - sb.width / 2) <= 0.6
			&& Math.abs(text.y + text.height / 2 - sb.y - sb.height / 2) <= 1, [sb, text]);
		var idleHooks = Pointer.hooks.length;
		value.set(1.333); settle();
		check('$size programmatic value snaps on the min-anchored decimal grid without callback', value.get() == 1.35 && changes == 0);
		hover("#single"); Pointer.wheel(tree, 0, 40); settle();
		check('$size wheel increments decimal steps once', value.get() == 1.4 && changes == 1 && parentWheels == 0);
		Pointer.wheel(tree, 0, -120); settle();
		check('$size wheel batches preserve decimal precision', value.get() == 1.25 && changes == 2);
		moveTo("#single", 0.75); Pointer.press(tree); settle();
		check('$size press uses actual bordered range travel', value.get() == 1.8 && Pointer.hooks.length == idleHooks + 1, value.get());
		Pointer.move(tree, 500, 280); settle();
		check('$size captured drag continues outside and clamps', value.get() == 2.05, value.get());
		Pointer.release(tree); settle();
		var released = changes;
		Pointer.move(tree, 1, 1); settle();
		check('$size release removes capture and stops edits', Pointer.hooks.length == idleHooks && changes == released);
		Focus.set(Interaction.byId(tree, node("#single").id), true);
		Keyboard.input(tree, key(Named(Home), Home)); settle();
		var home = value.get();
		Keyboard.input(tree, key(Named(ArrowRight), ArrowRight)); settle();
		var arrow = value.get();
		Keyboard.input(tree, key(Named(End), End)); settle();
		check('$size gauge retains range keyboard keys', home == 1.05 && arrow == 1.1 && value.get() == 2.05);
		value.set(Math.NaN); settle();
		check('$size empty numeric state becomes the lower bound', value.get() == 1.05, value.get());

		// The two visible grips delegate to two core ranges; edits cannot cross.
		lower.set(1.1); upper.set(1.8); settle();
		press("#lower > .thumb");
		check('$size lower grip focuses its core range', Focus.of(tree).node.id == node("#lower").id);
		moveTo("#lower", 0.4); settle();
		Pointer.release(tree); settle();
		check('$size lower grip drags independently', lower.get() == 1.45 && upper.get() == 1.8, [lower.get(), upper.get()]);
		press("#upper > .thumb"); moveTo("#upper", 0.95); settle(); Pointer.release(tree); settle();
		check('$size upper grip drags independently', lower.get() == 1.45 && upper.get() == 2.0);
		var before = intervals;
		hover("#lower > .thumb"); Pointer.wheel(tree, 0, 40); settle();
		check('$size wheel chooses the near lower endpoint', lower.get() == 1.5 && upper.get() == 2 && intervals == before + 1);
		hover("#upper > .thumb"); Pointer.wheel(tree, 0, -40); settle();
		check('$size wheel chooses the near upper endpoint', lower.get() == 1.5 && upper.get() == 1.95);
		Focus.set(Interaction.byId(tree, node("#lower").id), true);
		Keyboard.input(tree, key(Named(End), End)); settle();
		before = intervals;
		Keyboard.input(tree, key(Named(ArrowRight), ArrowRight)); settle();
		check('$size lower endpoint stops at upper without a redundant callback', lower.get() == upper.get() && intervals == before);
		Keyboard.input(tree, key(Named(Tab), Tab)); settle();
		check('$size Tab visits lower then upper', Focus.of(tree).node.id == node("#upper").id);
		Keyboard.input(tree, key(Named(Home), Home)); settle();
		check('$size upper endpoint stops at lower', lower.get() == upper.get());
		// Coincident grips remain reachable by pressing again.
		press("#upper > .thumb"); var first = Focus.of(tree).node.id; Pointer.release(tree); settle();
		press("#upper > .thumb"); var second = Focus.of(tree).node.id; Pointer.release(tree); settle();
		check('$size coincident grips alternate', first != second);
		lower.set(9); settle();
		check('$size programmatic lower cannot cross upper', lower.get() == upper.get());
		upper.set(-9); settle();
		check('$size programmatic upper cannot cross lower', lower.get() == upper.get());
		lower.set(1.3); upper.set(1.9); value.set(1.6); settle();
		form.get().requestSubmit();
		check('$size gauges submit their named numeric values', submitted != null && submitted.get("gain") == "1.6"
			&& submitted.get("low") == "1.3" && submitted.get("high") == "1.9");
		form.get().reset(); settle();
		check('$size form reset restores all three range values', value.get() == 1.25 && lower.get() == 1.1 && upper.get() == 1.8,
			[value.get(), lower.get(), upper.get()]);

		// NumberInput shares this grid for both its buttons and its wheel.
		hover("#number"); Pointer.wheel(tree, 0, 40); settle();
		var number = ashui.ui.Input.at(tree, node("#number").id);
		check('$size NumberInput wheel uses a nonzero decimal base', number.valueAsNumber.get() == 1.25);
		Pointer.wheel(tree, 0, 80); settle();
		check('$size NumberInput clamps to the highest valid step below max', number.valueAsNumber.get() == 1.25);

		press("#single > .thumb"); disabled.set(true); settle();
		var frozen = value.get(), lo = lower.get(), hi = upper.get();
		check('$size disabling during a drag releases capture', Pointer.hooks.length == idleHooks);
		Pointer.move(tree, 500, 250); Pointer.release(tree); settle();
		hover("#single"); Pointer.wheel(tree, 0, 40);
		hover("#interval"); Pointer.wheel(tree, 0, 40); settle();
		check('$size disabled wheel edits bubble without changes', value.get() == frozen && lower.get() == lo && upper.get() == hi && parentWheels == 2);
		disabled.set(false); fieldsetDisabled.set(true); settle();
		hover("#interval"); Pointer.wheel(tree, 0, 40); settle();
		check('$size disabled fieldset also disables the interval adapter', lower.get() == lo && upper.get() == hi && parentWheels == 3);
		fieldsetDisabled.set(false); settle();
		press("#lower > .thumb");
		check('$size interval drag installs one capture', Pointer.hooks.length == idleHooks + 1);
		dispose();
		check('$size disposing during a drag releases capture and focus', Pointer.hooks.length == idleHooks && Focus.of(tree) == null);
		Pointer.release(tree); tree.dispose();
	}

	static function main():Void {
		for (size in [Size.Sm, Size.Md, Size.Lg]) variant(size);
		// Float steps printed in exponent form must not be rounded to integers.
		var tree = new LayoutTree(), stop = () -> {};
		var tiny = Signal.make(0.0000002);
		var gauge = Owner.root(tree, dispose -> {
			stop = dispose;
			return <number-gauge value={tiny} min={-0.0000001} max={0.0000004} step={0.0000001} />;
		});
		function settle() for (_ in 0...3) { tree.flush(); tree.computeLayout(gauge.node, 240, 32); }
		settle();
		Pointer.move(tree, 80, 16); Pointer.wheel(tree, 0, 40); settle();
		check("exponent-form steps retain fractional precision under the wheel", tiny.get() == 0.0000003, tiny.get());
		Pointer.wheel(tree, 0, 200); settle();
		check("exponent-form bounds retain the final valid step", tiny.get() == 0.0000004, tiny.get());
		stop(); tree.dispose();
		Sys.println('$checks checks: ' + (failures == 0 ? "ALL PASSED" : '$failures FAILED'));
		Sys.exit(failures == 0 ? 0 : 1);
	}
}
