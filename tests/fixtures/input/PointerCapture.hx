import ashui.input.Pointer;
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.ui.Div;

/** A node that captures the pointer gets its moves and release from anywhere; touches follow where they began. */
class PointerCapture {
	static var failures = 0;

	static function check(name:String, ok:Bool, ?detail:Dynamic) {
		Sys.println((ok ? "ok   " : "FAIL ") + name + (ok || detail == null ? "" : " " + detail));
		if (!ok)
			failures++;
	}

	static function main() {
		var tree = new LayoutTree();
		var log:Array<String> = [];
		var grabX = -1.0, grabY = -1.0, outerMoves = 0, touchX = -1.0, touchY = -1.0;
		var holder:Div = null, other:Div = null;
		var root:Div = Owner.root(tree, _ -> <div width={400} height={240} onPointerMove={_ -> outerMoves++}>
			${holder = <div position={ashui.types.Style.Position.Absolute} left={20} top={20} width={80} height={50}
				onPointerDown={e -> { e.capturePointer(); log.push("down"); }}
				onPointerMove={e -> { log.push("move"); grabX = e.localX; grabY = e.localY; }}
				onPointerUp={_ -> log.push("up")}
				onTouchStart={e -> log.push("t" + e.id + "start")}
				onTouchMove={e -> { log.push("t" + e.id + "move"); touchX = e.localX; touchY = e.localY; }}
				onTouchEnd={e -> log.push("t" + e.id + "end")}
				onTouchCancel={e -> log.push("t" + e.id + "cancel")} />}
			${other = <div position={ashui.types.Style.Position.Absolute} left={200} top={100} width={80} height={50}
				onPointerMove={_ -> log.push("other")} onPointerUp={_ -> log.push("otherup")} />}
		</div>);
		tree.flush();
		tree.computeLayout(root.node, 400, 240);

		Pointer.move(tree, 30, 30);
		Pointer.press(tree);
		log = [];
		Pointer.move(tree, 240, 120);
		check("a captured move goes to the holder, not the node under the pointer", log.join(",") == "move", log);
		check("its place is in the holder's box", grabX == 220 && grabY == 100, [grabX, grabY]);
		var before = outerMoves;
		Pointer.move(tree, 250, 130);
		check("and does not bubble to the holder's ancestors", outerMoves == before);
		Pointer.release(tree);
		check("the release goes to the holder", log[log.length - 1] == "up" && log.indexOf("otherup") < 0, log);
		log = [];
		Pointer.move(tree, 240, 120);
		check("after the release moves go to what is under the pointer", log.join(",") == "other", log);

		Pointer.move(tree, 240, 120);
		Pointer.press(tree);
		Pointer.release(tree);
		log = [];
		Pointer.move(tree, 30, 30);
		Pointer.press(tree);
		Pointer.release(tree);
		Pointer.move(tree, 240, 120);
		check("a press that did not capture leaves capture off", log.indexOf("other") >= 0, log);

		log = [];
		Pointer.touch(tree, 7, Started, 30, 30);
		Pointer.touch(tree, 9, Started, 50, 40);
		Pointer.touch(tree, 7, Moved, 300, 200);
		check("touches start on the node under them and move with their own id", log.join(",") == "t7start,t9start,t7move", log);
		check("a moved touch's place is in the node's box", touchX == 280 && touchY == 180, [touchX, touchY]);
		Pointer.touch(tree, 7, Ended, 300, 200);
		Pointer.touch(tree, 7, Moved, 10, 10);
		Pointer.touch(tree, 9, Cancelled, 50, 40);
		check("an ended touch is forgotten and a cancelled one is reported", log.join(",") == "t7start,t9start,t7move,t7end,t9cancel", log);
		log = [];
		Pointer.touch(tree, 3, Started, 390, 230);
		check("a touch on empty space reaches no handler", log.length == 0, log);
		Pointer.touch(tree, 3, Ended, 390, 230);
		Sys.println(failures == 0 ? "ALL PASSED" : '$failures FAILED');
		Sys.exit(failures == 0 ? 0 : 1);
	}
}
