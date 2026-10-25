import ashui.components.Dialog;
import ashui.components.Dialog.AlertDialog;
import ashui.components.Dialog.AlertDialogContent;
import ashui.components.Dialog.DialogContent;
import ashui.css.Css;
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.reactive.Reactive;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.ui.Div;

/** A dialog's panel built after the dialog, inside an `<if>`, still follows the dialog's open state. **/
class DialogLateContent {
	static var checks = 0;

	static function check(name:String, ok:Bool, ?detail:Dynamic):Void {
		if (!ok)
			throw name + (detail == null ? "" : ' ($detail)');
		checks++;
		Sys.println('ok   $name');
	}

	static function main():Void {
		ThemeState.init(DefaultTheme.bundle(), Light);
		var tree = new LayoutTree(), root:Div = null;
		var plain = signal(false), alert = signal(false), early = signal(false);
		root = Owner.root(tree, _ -> <div width={800} height={600}>
			<dialog open={plain}><if {plain.get()}><dialog-content id="late-dialog"><div width={50} height={20}/></dialog-content></if></dialog>
			<alert-dialog open={alert}><if {alert.get()}><alert-dialog-content id="late-alert"><div width={50} height={20}/></alert-dialog-content></if></alert-dialog>
			<dialog open={early}><dialog-content id="early-dialog"><div width={50} height={20}/></dialog-content></dialog>
		</div>);
		function settle()
			for (_ in 0...8) {
				ashui.animation.AnimationScheduler.main.tick(0.016);
				Css.update();
				tree.flush();
				tree.computeLayout(root.node, 800, 600);
			}
		function count(selector:String):Int
			return Css.query(tree, root.node.id, selector).length;
		settle();
		check("nothing is built or shown while the dialogs are closed", count("#late-dialog") == 0 && count("#late-alert") == 0);
		early.set(true);
		settle();
		check("a panel there from the start shows when its dialog opens", count("#early-dialog") == 1);
		plain.set(true);
		settle();
		check("a panel built inside an if shows when its dialog opens", count("#late-dialog") == 1, count("#late-dialog"));
		alert.set(true);
		settle();
		check("so does an alert dialog's", count("#late-alert") == 1, count("#late-alert"));
		Sys.println('$checks checks: ALL PASSED');
	}
}
