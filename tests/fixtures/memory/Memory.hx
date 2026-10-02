import ashui.layout.LayoutTree;
import ashui.reactive.Computed;
import ashui.reactive.Signal;
import ashui.types.Color;

/**
	Resident memory after each round of 50k allocations of one kind, with
	hl.Gc.major and, unless "noflush", a LayoutTree flush between rounds.
	Flat numbers mean the kind is reclaimed; with noflush, signals and
	computeds are never removed from Blinc's graph, which shows the contrast.

	Usage: memory.hl tree|color|signal|computed [noflush]
**/
class Memory {
	static function rssMb():Int {
		if (sys.FileSystem.exists("/proc/self/statm")) {
			var pages = Std.parseFloat(sys.io.File.read("/proc/self/statm").readLine().split(" ")[1]);
			return Std.int(pages * 4096.0 / 1048576.0);
		}
		// macOS: the shell's parent is this process.
		var p = new sys.io.Process("sh", ["-c", "ps -o rss= -p $PPID"]);
		var kb = Std.parseFloat(StringTools.trim(p.stdout.readAll().toString()));
		p.close();
		return Std.int(kb / 1024);
	}

	static function main() {
		var kind = Sys.args()[0];
		var flush = Sys.args()[1] != "noflush";
		var tree = new LayoutTree();
		var line = [];
		for (round in 0...8) {
			for (i in 0...50000)
				switch kind {
					case "tree": new LayoutTree().createNode();
					case "color": new Color(i);
					case "signal": Signal.make(i);
					case "computed": Computed.make(() -> i + 1);
					case other: throw 'unknown kind $other';
				}
			hl.Gc.major();
			if (flush)
				tree.flush();
			line.push(rssMb());
		}
		Sys.println('${StringTools.rpad(kind, " ", 9)} ${flush ? "flush  " : "noflush"}  ${line.join(" ")} MB');
	}
}
