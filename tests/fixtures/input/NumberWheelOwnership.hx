import ashui.components.NumberGauge;
import ashui.components.NumberInput;
import ashui.components.NumberRangeGauge;
import ashui.css.Css;
import ashui.css.Identity;
import ashui.debug.InputLog;
import ashui.input.Focus;
import ashui.input.InputClock;
import ashui.input.Interaction;
import ashui.input.Pointer;
import ashui.input.Scroll;
import ashui.layout.LayoutTree;
import ashui.layout.Node;
import ashui.layout.Prop;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.ui.Div;
import window.TouchPhase;

/** Real wheel gestures keep parent scrolling separate from numeric editing (095fab4). **/
class NumberWheelOwnership {
	static var checks = 0;
	static function check(name:String, ok:Bool, ?detail:Dynamic):Void {
		checks++;
		if (!ok) throw name + ": " + Std.string(detail);
		Sys.println("ok   " + name);
	}

	static function main():Void {
		run(true);
		run(false);
		nested();
		Sys.println('$checks checks: ALL PASSED');
	}

	/** Both NumberInput layouts retain the same scroll ownership (e1d5d1b). **/
	static function run(showSteps:Bool):Void {
		var tree = new LayoutTree(), stop = () -> {};
		var number = Signal.make(50.0), gauge = Signal.make(50.0), lower = Signal.make(20.0), upper = Signal.make(80.0);
		var root:Div = Owner.root(tree, dispose -> {
			stop = dispose;
			return <div width={420} height={250} id="scroller" class="flex-col overflow-y-auto">
				<div width={400} height={700} class="flex-col shrink-0 gap-4">
					<div id="space" height={50} class="shrink-0" />
					<number-input id="number" value={number} min={0} max={100} showStepButtons={showSteps} />
					<number-gauge id="gauge" value={gauge} max={100} />
					<number-range-gauge id="interval" lower={lower} upper={upper} max={100} />
				</div>
			</div>;
		});
		function settle() for (_ in 0...3) { tree.flush(); tree.computeLayout(root.node, 420, 250); }
		function node(selector:String):Node return Identity.of(tree, Css.query(tree, root.node.id, selector)[0]).node;
		function hover(selector:String) {
			var b = tree.getBounds(node(selector));
			var scroll = Scroll.of(root.node);
			Pointer.move(tree, b.x + b.width / 2 - scroll.x.get(), b.y + b.height / 2 - scroll.y.get());
		}
		var clock = 1.0;
		InputClock.source = () -> clock;
		settle();
		var scroll = Scroll.of(root.node), hooks = Pointer.hooks.length;
		for (selector in ["#number", "#gauge", "#interval"]) {
			scroll.scrollTo(0, 0); settle(); clock += 1;
			hover("#space"); Pointer.wheel(tree, 0, -10); settle();
			var y = scroll.y.get();
			hover(selector); clock += 0.02; Pointer.wheel(tree, 0, -40); settle();
			check(selector + " cannot take over an active parent scroll", scroll.y.get() == y + 40
				&& number.get() == 50 && gauge.get() == 50 && lower.get() == 20 && upper.get() == 80, scroll.y.get());
		}
		scroll.scrollTo(0, 0); settle(); clock += 1;
		// Scroll content moves a numeric input under a stationary pointer.
		Pointer.move(tree, 40, 35); Pointer.wheel(tree, 0, -40); settle();
		check("scrolling moves the number field under the stationary pointer",
			Lambda.exists(tree.hitTest(40, 35), hit -> hit.id == node("#number").id));
		Pointer.wheel(tree, 0, -40); settle();
		check("stationary-pointer scrolling never edits the revealed number", number.get() == 50 && scroll.y.get() == 80);
		scroll.scrollTo(0, 0); settle(); clock += 1;
		Pointer.move(tree, 40, 35); Pointer.wheel(tree, 0, -10, Started); Pointer.wheel(tree, 0, -40, Moved); settle();
		Pointer.wheel(tree, 0, 0, Ended); clock += 0.02;
		Pointer.wheel(tree, 0, -40, Started); settle();
		check("macOS momentum phase handoff keeps scrolling instead of editing a revealed input", scroll.y.get() == 90
			&& number.get() == 50 && gauge.get() == 50);
		Pointer.wheel(tree, 0, 0, Ended);
		scroll.scrollTo(0, 0); settle(); clock += 1;
		hover("#space"); Pointer.wheel(tree, 0, -10, Started); settle();
		Focus.set(Interaction.of(node("#number")), true);
		hover("#number"); clock += 2; Pointer.wheel(tree, 0, -40, Moved); settle();
		check("an explicit trackpad gesture keeps ownership across a pause and input focus", number.get() == 50 && scroll.y.get() == 50);
		Pointer.wheel(tree, 0, 0, Ended);
		hover("#number"); var before = scroll.y.get();
		Pointer.wheel(tree, 0, 40, Started); Pointer.wheel(tree, 0, 0, Ended); settle();
		check("a new gesture over NumberInput edits it without scrolling the parent", number.get() == 51 && scroll.y.get() == before,
			[number.get(), scroll.y.get(), before, tree.getBounds(node("#number"))]);
		// Wheel mice infer a new gesture from inactivity, without a timer.
		scroll.scrollTo(0, 0); settle(); clock += 1;
		hover("#space"); Pointer.wheel(tree, 0, -10); settle();
		hover("#gauge"); clock += 0.3; before = scroll.y.get(); Pointer.wheel(tree, 0, 40); settle();
		check("after wheel inactivity a gauge can be edited without scrolling", gauge.get() == 51 && scroll.y.get() == before);
		Pointer.wheel(tree, 0, 20); clock += 0.3; Pointer.wheel(tree, 0, 20); settle();
		check("trackpad fractions from separate gestures do not combine", gauge.get() == 51, gauge.get());
		Pointer.wheel(tree, 0, 20); settle();
		check("fractions within one gesture still accumulate", gauge.get() == 52);
		// Cancelling overflow releases ownership even if the native gesture hasn't ended.
		clock += 1; scroll.scrollTo(0, 0); settle(); hover("#space"); Pointer.wheel(tree, 0, -10, Started); settle();
		root.node.set(Prop.OverflowY, ashui.types.Style.Overflow.Hidden); settle();
		hover("#gauge"); Pointer.wheel(tree, 0, 40, Moved); settle();
		check("disabling parent scrolling releases its wheel ownership", gauge.get() == 53,
			[gauge.get(), scroll.y.get()]);
		root.node.set(Prop.OverflowY, ashui.types.Style.Overflow.Scroll); settle();
		Pointer.wheel(tree, 0, 0, Cancelled);
		var log = InputLog.start();
		hover("#space"); Pointer.wheel(tree, 0, -10, Started); Pointer.wheel(tree, 0, 0, Ended); log.stop();
		var decoded:Array<ashui.debug.InputLog.InputEntry> = haxe.Unserializer.run(haxe.Serializer.run(log.entries));
		check("input logs serialize native wheel phase boundaries", decoded[1].record.match(WheelPhase(_, _, Started))
			&& decoded[2].record.match(WheelPhase(_, _, Ended)));
		// A gesture that begins at a scroll boundary still belongs to scrolling.
		scroll.scrollTo(0, 0); settle(); hover("#space"); Pointer.wheel(tree, 0, 40, Started);
		hover("#number"); before = number.get(); Pointer.wheel(tree, 0, -40, Moved); settle();
		check("reversing a parent gesture at its boundary cannot edit a number", number.get() == before && scroll.y.get() == 40);
		Pointer.wheel(tree, 0, 0, Cancelled); scroll.scrollTo(0, 0); settle(); hover("#number");
		Pointer.wheel(tree, 0, 40, Started); Pointer.wheel(tree, 0, 0, Ended); settle();
		check("cancelled gestures release ownership for deliberate numeric edits", number.get() == before + 1 && scroll.y.get() == 0);
		root.node.set(Prop.OverflowX, ashui.types.Style.Overflow.Scroll);
		node("#scroller > div").set(Prop.Width, (700 : Single)); settle();
		hover("#space"); Pointer.wheel(tree, -10, 0, Started); settle();
		hover("#number"); before = number.get(); Pointer.wheel(tree, 0, -40, Moved); settle();
		check("a parent's horizontal gesture also shields inputs from later vertical deltas", number.get() == before && scroll.x.get() == 10
			&& scroll.y.get() == 40);
		Pointer.wheel(tree, 0, 0, Ended);
		check("wheel ownership installs no pointer frame hooks", Pointer.hooks.length == hooks);
		InputClock.source = null;
		stop(); tree.dispose();
	}

	static function nested():Void {
		var tree = new LayoutTree(), stop = () -> {};
		var value = Signal.make(50.0);
		var root:Div = Owner.root(tree, dispose -> {
			stop = dispose;
			return <div width={400} height={250} class="flex-col overflow-y-auto">
				<div id="inner" width={380} height={180} class="flex-col shrink-0 overflow-y-auto">
					<div height={500} class="flex-col shrink-0">
						<div id="nested-space" height={40} class="shrink-0" />
						<number-gauge id="nested-number" value={value} />
					</div>
				</div>
				<div height={400} class="shrink-0" />
			</div>;
		});
		function settle() for (_ in 0...3) { tree.flush(); tree.computeLayout(root.node, 400, 250); }
		function node(selector:String):Node return Identity.of(tree, Css.query(tree, root.node.id, selector)[0]).node;
		settle();
		var outer = Scroll.of(root.node), inner = Scroll.of(node("#inner"));
		Pointer.move(tree, 60, 20); Pointer.wheel(tree, 0, -10, Started); settle();
		Pointer.move(tree, 60, 45); Pointer.wheel(tree, 0, -40, Moved); settle();
		check("nested scrolling skips numeric descendants of its owner", value.get() == 50 && inner.y.get() == 50 && outer.y.get() == 0);
		inner.scrollTo(0, inner.limits().y); settle();
		Pointer.move(tree, 60, 150); Pointer.wheel(tree, 0, -40, Moved); settle();
		check("an inner scroller at its boundary still bubbles to its parent", inner.y.get() == inner.limits().y && outer.y.get() == 40);
		Pointer.wheel(tree, 0, 0, Ended);
		outer.scrollTo(0, 0); inner.scrollTo(0, 0); settle();
		Pointer.move(tree, 60, 56); Pointer.wheel(tree, 0, 40, Started); settle();
		check("a fresh gesture edits a nested gauge without moving either scroller", value.get() == 51 && inner.y.get() == 0 && outer.y.get() == 0);
		Pointer.wheel(tree, 0, 0, Ended);
		stop(); tree.dispose();
	}
}
