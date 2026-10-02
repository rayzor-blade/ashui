/**
	Resident memory after each round of 50k handles that each own 16 KB of
	native memory, with hl.Gc.major() between rounds. Prints one line of MB.
**/
@:hlNative("memrepro")
extern class Native {
	static function make(bytes:Int):hl.Abstract<"memrepro_handle">;
}

class MemRepro {
	static function rssMb():Int {
		if (sys.FileSystem.exists("/proc/self/statm")) {
			var pages = Std.parseFloat(sys.io.File.read("/proc/self/statm").readLine().split(" ")[1]);
			return Std.int(pages * 4096.0 / 1048576.0);
		}
		var p = new sys.io.Process("sh", ["-c", "ps -o rss= -p $PPID"]);
		var kb = Std.parseFloat(StringTools.trim(p.stdout.readAll().toString()));
		p.close();
		return Std.int(kb / 1024);
	}

	static function main() {
		var line = [];
		for (round in 0...8) {
			for (i in 0...50000)
				Native.make(16384);
			hl.Gc.major();
			line.push(rssMb());
		}
		Sys.println(line.join(" ") + " MB");
	}
}
