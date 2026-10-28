# Desktop windows and menus

`WindowedApp.run` owns the platform event loop and a shared GPU device. Call `WindowedApp.open` to queue another window with its own UI builder:

```haxe
WindowedApp.run({title: "Project one", width: 1000, height: 700}, () -> {
    var first = WindowedApp.current;
    return new Button({onClick: _ -> WindowedApp.open(
        {title: "Project two", width: 800, height: 600},
        () -> new Text("Independent window")
    )}, [new Text("New window")]);
});
```

Each window has its own surface, renderer, layout tree, focus, input method,
theme, CSS cascade and viewport. Stylesheets installed before `run` are
inherited by every window. Install window-specific styles and themes in
that window's builder.

Reactive reads, watches, owners and scheduler callbacks retain their creation
context. `WindowedApp.current` identifies the window for that context.
Keep the instance when you need to control a specific window later.

The manager dispatches input and redraws only changed windows. It waits until
input, application work, an animation or a timer needs processing.
Closing the first window leaves other windows running. The loop returns
after the last window closes.

Each window releases its root owner, tree and surface independently.
The shared GPU device is released last. `windows()` returns a snapshot of
open windows; `windowRevision` changes when windows open or close.

Workers may call `open` to queue a builder, but builders and platform calls
run on the UI thread. Pass data from workers and create elements inside the
builder. If an additional window's builder fails, its resources are cleaned
up and the error is reported on stderr. Other windows continue running.

Use `onClose:Void->Bool` to defer closing, for example while asking whether
to save. Return false while the decision is pending. Then call the retained
window's `close()` to close without invoking the guard again.
Native close requests and `quit()` both invoke the guard.

After cleanup, `disposed` becomes true. Stop using that window's tree and renderer.

This requires hlwindow with xwindow's cross-window wait support: waiting on one window yields when another has events or a pending redraw. Rebuild the native adapter when upgrading.

## Application menus

`ashui.app.ApplicationMenu` installs a window's menu model; `update` replaces it.
On macOS, the focused window's menu appears in the system menu bar.
The default application menu supplies About, Hide and Quit. Pass the
application's guarded quit action to the constructor.

Native callbacks queue actions and wake the event loop. Actions run in their
originating UI context after the platform pump returns. Disposing the owner
removes its callbacks.

```haxe
var menus = new ApplicationMenu("Example", () -> {
    for (app in WindowedApp.windows()) app.quit();
});
menus.update([{label: "File", items: [
    {label: "New Window", run: openAnotherWindow},
    {separator: true},
    {label: "Close Window", run: WindowedApp.current.quit}
]}]);
```

A `MenuItem` accepts `enabled`, a display `shortcut`, and a `key` record with
a key name and `meta`, `ctrl`, `alt` and `shift` flags. On Windows and Linux,
render the model with `Menubar`, `MenubarMenu`, `MenubarTrigger`,
`MenubarContent` and `MenubarItem` from the components library.

`Keyboard.edit(tree, action)` sends undo, redo, cut, copy, paste or select-all
to the focused control.

Native lifecycle tests are in `tests/Windows.hx`; build with the usual UI class paths and `-D ashui_window`, and run on a desktop display.

## File and folder dialogs

`FileDialog.open(app, options, complete)` opens an asynchronous macOS sheet
on `app.window`. Options include `title`, `folder`, `directory` and `extensions`.
The completion callback runs in the window's UI context and receives a path,
or null on cancellation.

The returned function cancels the request. Window disposal also cancels it.
Cancel pending requests when replacing a workspace owner. Native callbacks
only queue results and wake the loop; application code runs after the pump returns.

Check `FileDialog.available()` before using this implementation on another
platform. `tests/FileDialogWindow.hx` tests native selection and cancellation.
