import ashui.app.WindowedApp;
import ashui.app.ApplicationMenu;
import ashui.app.FileDialog;
import ashui.reactive.Signal;

/** Manual native file-dialog smoke check, isolated from any editor workspace. */
class FileDialogWindow {
	static function main() {
		ashui.components.Library.use();
		WindowedApp.run({title:"RayDE Picker Check", width:640, height:360}, () -> {
			var app = WindowedApp.current;
			var status = Signal.make("Choose File → Open Project to test the attached browser.");
			function choose():Void FileDialog.open(app, {title:"Open Project", directory:Sys.getCwd(), extensions:["hxml", "json", "toml"]}, path -> {
				status.set(path == null ? "Selection cancelled" : "Opened: " + haxe.io.Path.withoutDirectory(path));
				Sys.println("picker-result: " + (path == null ? "cancelled" : path));
			});
			var menu = new ApplicationMenu("RayDE Picker Check", app.quit);
			menu.update([{label:"File", items:[{label:"Open Project…", run:choose}]}]);
			return <div class="flex flex-col gap-4 p-6"><text>${status.get()}</text></div>;
		});
	}
}
