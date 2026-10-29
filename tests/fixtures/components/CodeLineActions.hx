import ashui.components.CodeEditor;
import ashui.components.code.CodeEditorState;
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
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.ui.Ref;

/** Above-line actions share text geometry, retain button input, and mount only visible rows (93ce15e). **/
class CodeLineActions {
	static var checks = 0;
	static function check(name:String, ok:Bool, ?detail:Dynamic):Void {
		if (!ok) throw name + (detail == null ? "" : ' ($detail)');
		checks++; Sys.println('ok   $name');
	}
	static function near(a:Float, b:Float):Bool return Math.abs(a-b) < 1;

	static function main():Void {
		ThemeState.init(DefaultTheme.bundle(), Light);
		var source = 'class Counter {\n    static function main() {\n        trace("hello");\n    }\n}\n'
			+ [for (i in 0...500) 'var line$i = $i;'].join("\n");
		var text = Signal.make(source), locked = Signal.make(false), actionLocked = Signal.make(false), readOnly = Signal.make(false);
		var provided = Signal.make(([]:Array<ashui.components.code.CodeAnnotations.CodeLineActions>));
		var state = new CodeEditorState(text), mounted = Signal.make(true), ref = new Ref<CodeEditor>();
		var tree = new LayoutTree(), dispose:Void->Void = null, ran = 0;
		var root = Owner.root(tree, stop -> {
			dispose = stop;
			return <div width={720} height={360}>
				<if {mounted}>
					<code-editor ref={ref} state={state} language="haxe" width={720} height={360}
						gutterMarkers={true} compactGutter={true} minimap={true} disabled={locked} readOnly={readOnly} codeActions={provided} />
				</if>
			</div>;
		});
		function settle():Void for (_ in 0...8) {
			Css.update(); tree.flush(); tree.computeLayout(root.node,720,360);
		}
		function nodes(selector:String):Array<Node> return [for (id in Css.query(tree,root.node.id,selector)) new Node(id)];
		function gutter():Float return tree.getBounds(nodes(".ui-code-gutter")[0]).width;
		function click(node:Node):Void {
			var b = tree.getScrolledBounds(node);
			Pointer.move(tree,b.x+b.width/2,b.y+b.height/2); Pointer.press(tree); Pointer.release(tree); settle();
		}
		settle();
		var editor = ref.get(), baseGutter = gutter(), original = editor.rectAt(editor.document.lines[1].start);
		editor.actions("runner", [
			{line:0, actions:[{label:"Inspect",icon:'<svg viewBox="0 0 12 12"><path d="M1 1h10v10H1z" fill="currentColor"/></svg>',run:()->ran++}]},
			{line:1, actions:[{label:"Run",run:()->ran++,disabled:actionLocked},{label:"Debug",run:()->ran+=10}]},
			{line:-1, actions:[{label:"Invalid",run:()->throw "invalid action"}]}
		],true);
		settle();
		var rows = nodes(".ui-code-actions[data-line]"), first = tree.getScrolledBounds(rows[0]);
		var line = editor.rectAt(editor.document.lines[1].start), run = nodes('.ui-code-actions[data-line="1"] .ui-code-action')[0];
		var runBounds = tree.getScrolledBounds(run);
		check("actions do not reserve a gutter column",near(gutter(),baseGutter) && nodes(".ui-code-marker-slot").length==0);
		check("a first-line action has space above the first source line",rows.length==2 && first.height>0 && near(editor.rectAt(0).y,first.y+first.height));
		check("action rows shift subsequent source lines",near(line.y-original.y,2*first.height));
		check("commands align with the source indentation",near(runBounds.x,line.x+editor.metrics.xAt(editor.document.lines[1],4)));
		var label = nodes('.ui-code-actions[data-line="1"] .ui-code-action-label')[0];
		check("button padding does not indent the action label",near(tree.getScrolledBounds(label).x,runBounds.x));
		var icon = nodes('.ui-code-actions[data-line="0"] .ui-code-action-icon')[0];
		check("leading icons align with the code column too",near(tree.getScrolledBounds(icon).x,editor.rectAt(0).x));
		check("action space does not map to text",editor.offsetAt(runBounds.x+2,runBounds.y+2)==-1);
		editor.focus(); editor.select(2,2); settle();
		check("caret changes retain existing action buttons",tree.getBounds(run)!=null);
		click(run);
		check("pointer activation runs a command without editing or moving the caret",ran==1 && text.get()==source && editor.editing.caret.get()==2);
		Focus.set(Interaction.byId(tree,run.id),true);
		Keyboard.input(tree,Input(Code(Enter),Named(Enter),None,Standard,Pressed,false,Unavailable)); settle();
		check("Enter activates the standard button without reaching the editor",ran==2 && text.get()==source);
		actionLocked.set(true); settle(); click(run);
		check("an individual action can be disabled reactively",ran==2 && Interaction.byId(tree,run.id).isDisabled());
		actionLocked.set(false); locked.set(true); settle(); click(run);
		check("disabled editors reject action input",ran==2);
		locked.set(false); settle();
		readOnly.set(true); settle(); click(run);
		check("read-only code still supports commands",ran==3 && text.get()==source);
		readOnly.set(false);
		var oldY = editor.rectAt(editor.document.lines[1].start).y;
		Identity.declare(editor.node,"--ui-code-actions-height","32px"); settle();
		check("CSS action height updates text geometry",near(editor.rectAt(editor.document.lines[1].start).y-oldY,16));

		editor.markers("debugger",[{line:1,className:"ui-code-marker-breakpoint"}]); settle();
		check("breakpoints coexist independently with line actions",nodes(".ui-code-marker-breakpoint").length==1 && nodes(".ui-code-action").length==3 && near(gutter(),baseGutter+18));
		editor.actions("runner",[]); settle();
		check("clearing actions preserves gutter markers",nodes(".ui-code-action").length==0 && nodes(".ui-code-marker-breakpoint").length==1);
		editor.markers("debugger",[]);

		editor.actions("runner",[{line:1,actions:[{label:"Run",run:()->ran++}]}],true);
		editor.actions("review",[{line:1,actions:[{label:"Review",run:()->ran++}]}]); settle();
		check("independent producers share one row on the same line",nodes(".ui-code-actions[data-line]").length==1 && nodes(".ui-code-action").length==2);
		editor.toggleFold(0); settle();
		check("folded source lines hide their action space",nodes(".ui-code-actions[data-line]").length==0);
		editor.toggleFold(0); settle();
		check("unfolding restores the action row",nodes(".ui-code-action").length==2);
		editor.applyEdits([{from:0,to:0,text:"// inserted\n"}]); settle();
		check("tracked actions follow edits while fixed actions keep their line",editor.actionLinesOf("runner")[0]==2 && editor.actionLinesOf("review")[0]==1);
		editor.actions("review",[]); editor.actions("runner",[]);

		provided.set([{line:2,actions:[{label:"From HXX",run:()->ran++}]}]); settle();
		check("reactive HXX props install line actions",nodes(".ui-code-action").length==1);
		provided.set([]); settle();
		check("reactive HXX props clear their actions",nodes(".ui-code-action").length==0);
		editor.actions("many",[for(i in 0...editor.document.lines.length) {line:i,actions:[{label:"Run",run:()->ran++}]}]); settle();
		var count = nodes(".ui-code-action").length;
		check("large action sets mount only viewport rows",count>0 && count<40,count);
		editor.scroll.jumpTo(0,9000); settle();
		check("scrolling replaces visible action rows with a bounded number of controls",nodes(".ui-code-action").length>0 && nodes(".ui-code-action").length<40 && nodes('.ui-code-actions[data-line="0"]').length==0);
		editor.actions("many",[]); settle();
		check("clearing a large set releases every action row and probe",nodes(".ui-code-actions").length==0);
		editor.actions("persist",[{line:200,actions:[{label:"Run",run:()->ran++}]}]);
		mounted.set(false); settle();
		check("disposing a view removes controls and retains action metadata",nodes(".ui-code-action").length==0 && !state.mounted && state.annotations.actionLinesOf("persist")[0]==200);
		var hooks = LayoutTree.layoutHooks.length, restyles = Css.restyled.length;
		mounted.set(true); settle(); editor=ref.get();
		var offset = editor.document.lines[200].start; editor.focus(); editor.select(offset,offset); settle();
		check("remounting restores actions without retaining old views",editor.actionLinesOf("persist")[0]==200 && nodes(".ui-code-action").length==1,
			[editor.actionLinesOf("persist"),nodes(".ui-code-action").length,editor.scroll.y.get()]);
		text.set("short"); settle();
		check("source replacement safely removes actions beyond the new document",nodes(".ui-code-action").length==0 && editor.document.lines.length==1);
		dispose();
		check("owner disposal releases editor hooks and action interactions",LayoutTree.layoutHooks.length==hooks && Css.restyled.length==restyles && Interaction.inTree(tree).length==0,
			[hooks,LayoutTree.layoutHooks.length,restyles,Css.restyled.length,Interaction.inTree(tree).length]);
		tree.dispose();
		Sys.println('$checks checks: ALL PASSED');
	}
}
