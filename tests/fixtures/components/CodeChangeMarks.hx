import ashui.components.CodeEditor;
import ashui.css.Css;
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.reactive.Reactive;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.ui.Div;
import ashui.ui.Ref;

/** Boundary markers below a line, and marks in the minimap from decorations and markers that ask for them. **/
class CodeChangeMarks {
	static var checks = 0;

	static function check(name:String, ok:Bool, ?detail:Dynamic):Void {
		if (!ok)
			throw name + (detail == null ? "" : ' ($detail)');
		checks++;
		Sys.println('ok   $name');
	}

	static function main():Void {
		ThemeState.init(DefaultTheme.bundle(), Light);
		var source = [for (i in 0...200) 'line $i'].join("\n");
		var value = signal(source), ref = new Ref<CodeEditor>(), tree = new LayoutTree(), stop:Void->Void = null;
		var root = Owner.root(tree, s -> {
			stop = s;
			return <div width={700} height={400}><code-editor ref={ref} value={value} language="plain" minimap={true} gutterMarkers={true} width={700} height={400}/></div>;
		});
		function settle()
			for (_ in 0...8) {
				Css.update();
				tree.flush();
				tree.computeLayout(root.node, 700, 400);
			}
		settle();
		var ed = ref.get(), a = ed.annotations;
		check("nothing is marked at first", a.boundaryAt(3) == null && a.minimapMarks(100).length == 0);
		ed.markers("scm", [
			{line: 3, className: "ui-code-change-added", bar: true, minimap: true},
			{line: 7, className: "ui-code-change-removed", boundary: true, minimap: true},
			{line: 7, className: "ui-code-change-modified"}
		]);
		settle();
		check("a boundary marker is found below its line", a.boundaryAt(7) != null && a.boundaryAt(7).className == "ui-code-change-removed");
		check("a boundary marker does not take the line's own slot", a.markerAt(7) != null && a.markerAt(7).className == "ui-code-change-modified");
		check("a change bar is in its own lane, not the marker slot", a.barAt(3) != null && a.markerAt(3) == null && a.boundaryAt(3) == null);
		check("a line's marker and bar are both kept", {
			ed.markers("dbg", [{line: 3, className: "ui-code-marker-breakpoint"}]);
			a.markerAt(3) != null && a.markerAt(3).className == "ui-code-marker-breakpoint" && a.barAt(3) != null;
		});
		ed.markers("dbg", []);
		var marks = a.minimapMarks(100);
		check("markers that ask are marked in the minimap as bars", marks.length == 2 && marks[0].bar && marks[1].bar, marks);
		check("a marker that does not ask is not", [for (m in marks) m.className].indexOf("ui-code-change-modified") < 0);
		var start = ed.document.lines[10].start, end = ed.document.lines[14].start - 1;
		ed.decorate("find", [{from: start, to: end, className: "ui-code-change-added", minimap: true}, {from: start, to: end, className: "plain"}]);
		var all = a.minimapMarks(100);
		check("a decoration marks every line it touches, a full row each", all.filter(m -> !m.bar).length == 4, all);
		check("the limit bounds the marks", a.minimapMarks(3).length == 3);
		ed.markers("scm", []);
		ed.decorate("find", []);
		check("clearing the sets clears the marks", a.minimapMarks(100).length == 0 && a.boundaryAt(7) == null);
		stop();
		tree.dispose();
		Sys.println('$checks checks: ALL PASSED');
	}
}
