import ashui.app.ApplicationMenu;
import ashui.app.FileDialog;
import ashui.app.WindowedApp;
import ashui.animation.AnimationScheduler;

@:access(ashui.app.ApplicationMenu)
@:access(ashui.app.FileDialog)
class MenuDialogChecks {
	static function main():Void {
		if (!FileDialog.available()) return;
		var failure:Dynamic = null, opened = 0, finished = false;
		WindowedApp.run({title:"Queued project picker check",width:640,height:360}, () -> {
			var app = WindowedApp.current;
			var menu = new ApplicationMenu("Project Picker Check", app.quit);
			var cancel:Void->Void = null;
			function choose():Void {
				opened++;
				cancel = FileDialog.open(app, {title:"Open Project",directory:Sys.getCwd(),extensions:["hxml","json","toml"]}, _ -> {});
			}
			AnimationScheduler.main.after(.1, () -> {
				try {
					menu.update([{label:"File",items:[{label:"Open Project…",run:choose}]}]);
					var queued:Int = haxe.Json.parse(menu.payload).menus[0].items[0].id;
					menu.update([{label:"File",items:[{label:"Open Project…",run:choose}]}]);
					var sent = false;
					ApplicationMenu.drain(() -> {if (sent) return 0; sent = true; return queued;});
					if (opened != 1 || cancel == null || Lambda.count(FileDialog.requests) != 1) throw "One queued menu click did not open exactly one native picker: " + haxe.Json.stringify({opened:opened,cancellable:cancel != null,pending:Lambda.count(FileDialog.requests)});
					cancel();
					if (Lambda.count(FileDialog.requests) != 0) throw "Cancelled native picker retained its callback";
					finished = true;
				} catch (error:Dynamic) failure = error;
				app.quit();
			});
			AnimationScheduler.main.after(8, () -> {failure = "Native picker check timed out"; app.quit();});
			return <div><text>Queued File → Open Project check</text></div>;
		});
		if (failure != null) throw failure;
		if (!finished) throw "Native picker check did not finish";
		Sys.println("native project picker: a click queued before a menu rebuild opens one attached dialog and releases its callback on cancellation");
	}
}
