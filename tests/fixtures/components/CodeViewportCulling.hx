import ashui.components.CodeEditor;
import ashui.components.code.CodeMetrics;
import ashui.core.render.Offscreen;
import ashui.css.Css;
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.ui.Ref;

@:access(ashui.components.CodeEditor)
class CodeViewportCulling {
	static function check(ok:Bool,message:String):Void if (!ok) throw message;
	static function main():Void {
		var geometry:ashui.components.code.CodeMetrics.CodeLineMetrics = {
			expanded:"a🙂éz",columns:[0,1,2,3,4,5,6],width:40,ordered:true,
			stops:[for (stop in [{index:0,x:0.},{index:1,x:8.},{index:3,x:24.},{index:5,x:32.},{index:6,x:40.}]) {index:stop.index,x:stop.x,line:0}]
		};
		var span = CodeMetrics.window(geometry,12,27);
		check(span.from == 1 && span.to == 5,"Clipping split a measured character cluster");
		var reordered:ashui.components.code.CodeMetrics.CodeLineMetrics = {expanded:geometry.expanded,columns:geometry.columns,width:geometry.width,stops:geometry.stops,ordered:false};
		span = CodeMetrics.window(reordered,12,27);
		check(span.from == 0 && span.to == 6,"Visually reordered text lost shaping context");
		ashui.theme.ThemeState.init(ashui.theme.themes.RestrainedTheme.bundle(),Dark);
		for (language in ["plain","haxe"]) {
			var line = "\t// " + [for (_ in 0...200) "long comment text "].join("");
			var source = [for (i in 0...400) line + i].join("\n"), ref = new Ref<CodeEditor>(), tree = new LayoutTree(), dispose:Void->Void = null;
			var root = Owner.root(tree,cleanup -> {
				dispose = cleanup;
				return <div class="flex flex-col" width={900} height={500}><code-editor ref={ref} value={source} language={language} minimap={true} class="flex-1 min-h-0"/></div>;
			});
			function settle():Void for (_ in 0...6) { Offscreen.advance(.02); Css.setViewport(900,500); Css.update(); tree.flush(); tree.computeLayout(root.node,900,500); }
			function inspect():Void {
				var editor = ref.get(), count = editor.shownRowCount();
				check(count > 10 && count <= Math.ceil(500/editor.metrics.lineHeight)+8,"Rows were not virtualized");
				for (row in editor.cachedRows) for (run in row.runs) check(run.text.length < 400,"A long run was submitted outside horizontal overscan");
				check(editor.value.get() == source && editor.metrics.measure(editor.document.lines[0]).width > 10000,"Culling changed the document or horizontal scroll extent");
			}
			try {
				settle(); inspect();
				var editor = ref.get(), last = source.length-3, caret = editor.metrics.stopAt(last);
				check(caret.x > 10000 && caret.index == last,"Offscreen caret geometry was truncated");
				editor.scroll.jumpTo(3000,editor.metrics.lineHeight*12+1); settle(); inspect();
				for (row in editor.cachedRows) for (run in row.runs) check(run.x > 2000,"Horizontal panning left submitted text anchored at the line's origin");
				var previous = editor.cachedRows.copy();
				editor.scroll.jumpTo(3001,editor.scroll.y.get()+1); settle();
				check(previous.length == editor.cachedRows.length,"Subline scrolling changed the row window");
				for (i in 0...previous.length) check(previous[i] == editor.cachedRows[i],"Subline scrolling rebuilt an unchanged row");
				editor.scroll.jumpTo(0,0); settle(); inspect();
			} catch (error:Dynamic) { dispose(); tree.dispose(); throw error; }
			dispose(); tree.dispose();
		}
		Sys.println("Editor culling: bounded rows and text, stable subline scroll, full caret geometry, horizontal pans and cluster boundaries passed");
	}
}
