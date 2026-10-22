import ashui.app.WindowedApp;
import ashui.animation.AnimationScheduler;
import ashui.core.UiContext;
import ashui.css.Css;
import ashui.css.Identity;
import ashui.layout.Element;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.reactive.Computed;
import ashui.reactive.Watch;
import ashui.theme.ThemeState;

/** Native multiwindow lifecycle, event routing, deferred contexts and CSS isolation. */
class Windows {
	static var a:WindowedApp;
	static var b:WindowedApp;
	static var c:WindowedApp;
	static var d:WindowedApp;
	static var ended = new Map<String, Bool>();
	static var roots = new Map<String, Element>();
	static var count = Signal.make(0);
	static var bRead:Computed<String>;
	static var bReaction = false;
	static var veto = true;
	static var primaryClosed = false;
	static var finalCheck = false;
	static var failure:Dynamic;
	static var late:ashui.animation.AnimationScheduler.Timer;
	static final hostContext = UiContext.current;

	static function after(seconds:Float, fn:Void->Void):Void
		hostContext.run(() -> AnimationScheduler.main.after(seconds, () -> {
			if (failure != null)
				return;
			try
				fn()
			catch (error:Dynamic) {
				failure = error;
				for (app in WindowedApp.windows()) {
					@:privateAccess app.config.onClose = null;
					app.quit();
				}
			}
		}));

	static function until(ready:Void->Bool, fn:Void->Void):Void
		after(.05, () -> {
			if (ready())
				fn();
			else
				until(ready, fn);
		});

	static function check(ok:Bool, message:String):Void {
		if (!ok)
			throw message;
	}

	static function page(name:String):Element {
		var app = WindowedApp.current;
		check(app != null, "builder has a current window");
		Owner.onCleanup(() -> ended.set(name, true));
		var root = <div id="probe"><text>{name}</text></div>;
		roots.set(name, root);
		if (name == "B") {
			bRead = Computed.make(() -> Std.string(ThemeState.get().scheme()) + count.get());
			new Watch(() -> count.get(), n -> if (n == 1) {
				check(WindowedApp.current == app, "watch retains its window context");
				check(ThemeState.get().scheme() == Light, "watch reads its window theme");
				bReaction = true;
			});
		}
		return root;
	}

	static function width(app:WindowedApp, name:String):String
		return app.context.run(() -> {
			var el = roots.get(name);
			return Css.computed(Identity.of(el.tree, el.node.id), "width");
		});

	static function main() {
		ThemeState.init(ashui.theme.themes.ExpressiveTheme.bundle(), Dark);
		Css.load("#probe { width: 90px; height: 80px; background: var(--background); } @media (max-width: 500px) { #probe { width: 70px; } }");
		var timer = AnimationScheduler.main;
		WindowedApp.run({
			title: "Ashui window A",
			width: 640,
			height: 400,
			appearance: Dark
		}, () -> {
			a = WindowedApp.current;
			late = timer.after(100, () -> { throw "closed window timer fired"; });
			after(10, () -> {
				throw "windows test timed out";
			});
			WindowedApp.open({
				title: "Ashui window B",
				width: 420,
				height: 300,
				appearance: Light
			}, () -> {
				b = WindowedApp.current;
				return page("B");
			});
			WindowedApp.open({
				title: "Ashui window C",
				width: 720,
				height: 350,
				appearance: Dark,
				onClose: () -> !veto
			}, () -> {
				c = WindowedApp.current;
				return page("C");
			});
			until(() -> b != null && c != null && a.frames > 0 && b.frames > 0 && c.frames > 0, () -> {
				check(WindowedApp.windows().length == 3, "queued windows opened");
				check(a.device == b.device && b.device == c.device, "windows share the GPU device");
				check(a.tree != b.tree && b.tree != c.tree, "each window has a tree");
				check(b.context.run(() -> ThemeState.get().color(Primary).rgb()) == ashui.theme.themes.ExpressiveTheme.bundle().forScheme(Light).colors.get(Primary).rgb(), "application theme is inherited");
				check(width(a, "A") == "90px" && width(b, "B") == "70px", "media queries are window-local: A="
					+ width(a, "A")
					+ " B="
					+ width(b, "B"));
				check(bRead.get() == "00", "computed uses its creation context");
				count.set(1);
				c.context.run(c.quit);
				check(!c.disposed, "close guard may defer closing");
				WindowedApp.open({title:"Failed window", width:300, height:200}, () -> {
					Owner.onCleanup(() -> ended.set("failed", true));
					throw "expected test builder failure";
					return null;
				});
				a.quit();
				until(() -> a.disposed && bReaction, () -> {
					check(a.disposed && ended.get("A"), "closing primary releases its owner");
				check(late.cancelled, "window teardown releases its deferred callbacks");
				check(ended.get("failed") && WindowedApp.windows().length == 2, "a failed builder releases its owner without closing other windows");
				check(!@:privateAccess ashui.css.NativeCascade.reordered.exists(a.tree), "closed tree has no queued cascade work");
				check(!@:privateAccess ashui.css.Css.pending.exists(a.tree), "closed tree has no queued stylesheet work");
					check(!b.disposed && b.frames > 0, "secondary survives primary close");
					check(bRead.get() == "01" && bReaction, "cross-window reactive work stays in its context");
					primaryClosed = true;
					b.window.setTitle("Ashui surviving window B");
					b.window.focus();
					WindowedApp.open({
						title: "Ashui window D",
						width: 300,
						height: 250,
						appearance: Light
					}, () -> {
						d = WindowedApp.current;
						return page("D");
					});
					until(() -> d != null && d.frames > 0, () -> {
						check(d != null && d.frames > 0, "can open another window after primary close");
						veto = false;
						c.context.run(c.quit);
						d.context.run(d.quit);
						until(() -> c.disposed && d.disposed, () -> {
							check(ended.get("C") && ended.get("D"), "secondary owners released");
							check(WindowedApp.windows().length == 1, "only surviving window remains");
							check(b.frames < 30, "static windows do not redraw continuously");
							finalCheck = true;
							b.context.run(b.quit);
						});
					});
				});
			});
			return page("A");
		});
		if (failure != null)
			throw failure;
		check(primaryClosed && finalCheck && ended.get("B"), "last close completes the application");
		check(WindowedApp.current == null && WindowedApp.windows().length == 0, "manager releases its windows");
		Sys.println("windows: PASS");
	}
}
