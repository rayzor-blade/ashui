import ashui.components.Button;
import ashui.css.Css;
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.ui.Div;

/**
	What mounting a control costs: builds `count` of one kind under one Owner, runs three style and layout passes, and
	prints the heap the GC keeps and the process footprint per element, before and after disposal. `CENSUS=<file>` writes
	Ash's typed heap census after the build (its `external-bytes` is a collector pressure charge, not memory);
	`NOSETTLE=1` skips the style passes; `HOLD=1` waits 25 s for `heap`, `vmmap` or `malloc_history` on the process.

	Usage: nodecost.hl div|text|hover|part|focusable|p-class|p-tag|p-variant|p-other|button <count>
**/
class NodeCost {
	static function footprintKb():Int {
		var p = new sys.io.Process("sh", ["-c", "footprint -p $PPID 2>/dev/null | grep -m1 -i 'Footprint:'"]);
		var line = p.stdout.readAll().toString();
		p.close();
		var r = ~/Footprint: ([0-9.]+) (KB|MB|GB)/;
		if (!r.match(line)) return -1;
		var v = Std.parseFloat(r.matched(1));
		return Std.int(v * (r.matched(2) == "GB" ? 1048576 : r.matched(2) == "MB" ? 1024 : 1));
	}

	static function heapKb():Int {
		hl.Gc.major();
		hl.Gc.major();
		return Std.int(hl.Gc.stats().currentMemory / 1024);
	}

	static function focusable():ashui.layout.Element {
		var box = ashui.components.Library.part("ui-button", "button", ["variant" => "ghost", "size" => "md"], [], null);
		ashui.input.Interaction.of(box.node).setFocusable(true);
		return box;
	}

	static function main() {
		ThemeState.init(DefaultTheme.bundle(), Light);
		var kind = Sys.args()[0], n = Std.parseInt(Sys.args()[1]);
		var tree = new LayoutTree();
		var stops = [];
		var root:Div = null;
		function settle()
			for (_ in 0...3) {
				Css.update();
				tree.flush();
				tree.computeLayout(root.node, 1200, 900);
			}
		var s0 = Owner.root(tree, stop -> {
			root = new Div({width: 1200, height: 900}, tree);
			stops.push(stop);
			root;
		});
		settle();
		var h0 = heapKb(), f0 = footprintKb();
		var items = [for (i in 0...n) i];
		Owner.root(tree, stop -> {
			stops.push(stop);
			var all = switch kind {
				case "div": <div width={1200}><for {i in items}><div width={20} height={20}/></for></div>;
				case "text": <div width={1200}><for {i in items}><text>Run</text></for></div>;
				case "hover": <div width={1200}><for {i in items}><div class="ui-button" width={60} height={30}/></for></div>;
				case "part": <div width={1200}><for {i in items}>{ashui.components.Library.part("ui-button", "button", ["variant" => "ghost", "size" => "md"], [], null)}</for></div>;
				case "focusable": <div width={1200}><for {i in items}>{focusable()}</for></div>;
				case "p-class": <div width={1200}><for {i in items}>{ashui.components.Library.part("ui-button", null, null, [], null)}</for></div>;
				case "p-tag": <div width={1200}><for {i in items}>{ashui.components.Library.part("ui-button", "button", null, [], null)}</for></div>;
				case "p-variant": <div width={1200}><for {i in items}>{ashui.components.Library.part("ui-button", null, ["variant" => "ghost"], [], null)}</for></div>;
				case "p-other": <div width={1200}><for {i in items}>{ashui.components.Library.part("ui-card", null, null, [], null)}</for></div>;
				case "button": <div width={1200}><for {i in items}><button variant={Ghost}>Run</button></for></div>;
				case other: throw other;
			};
			root.appendChild(all);
			all;
		});
		if (Sys.getEnv("NOSETTLE") == null) settle();
		var h1 = heapKb(), f1 = footprintKb();
		if (Sys.getEnv("CENSUS") != null) { hl.Gc.dumpMemory(Sys.getEnv("CENSUS")); }
		Sys.println('$kind x$n: heap +${Std.int((h1 - h0) / n * 10) / 10} KB each (gc), footprint +${Std.int((f1 - f0) / n * 10) / 10} KB each');
		if (Sys.getEnv("HOLD") != null) Sys.sleep(25);
		for (stop in stops) stop();
		settle();
		var h2 = heapKb(), f2 = footprintKb();
		Sys.println('  after dispose: heap ${Std.int((h2 - h0) / n * 10) / 10} KB each, footprint ${Std.int((f2 - f0) / n * 10) / 10} KB each');
	}
}
