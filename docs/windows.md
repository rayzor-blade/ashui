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

Each window has its own surface, renderer, layout tree, focus, input method, theme, stylesheet cascade and viewport. Stylesheets installed before `run` are inherited by each window. Install window-specific styles or themes in its builder. Reactive reads, watches, owners and scheduler callbacks retain their creation context. `WindowedApp.current` identifies that context's window; retain the instance when controlling a specific window later.

The manager dispatches each window's input and draws only changed windows. It waits until input, application work, an animation or a timer requires a turn. Closing the first window leaves the others running. The loop returns when the last window closes. It releases each window's root owner, tree and surface independently, and releases the shared device last. `windows()` returns a snapshot; `windowRevision` changes as windows open and close.

`open` may enqueue a builder from a worker. Builders and platform calls run on the UI thread. Queue data only; do not create elements on workers. An additional window whose builder fails is cleaned up and reported on stderr while other windows continue.

A config's `onClose:Void->Bool` may defer closing. Return false while showing a save decision, then call the retained window's `quit()` after approval. Both native close requests and `quit()` pass through the guard. `disposed` becomes true after cleanup; its tree and renderer must then no longer be used.

This requires hlwindow with xwindow's cross-window wait support: waiting on one window yields when another has events or a pending redraw. Rebuild the native adapter when upgrading.

## Application menus

`ashui.app.ApplicationMenu` installs a menu model for its window. `update` replaces that model; macOS activates the focused window's menu in the system menu bar. Actions are queued by the native callback, wake the event loop, and execute in the originating UI context after the platform pump returns. Owner disposal removes its callbacks. The application menu supplies About, Hide and Quit. Pass the application's guarded quit action to its constructor.

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

A `MenuItem` can include `enabled`, a display `shortcut`, and a `key` record with a key name and `meta`, `ctrl`, `alt`, `shift` flags. On Windows and Linux render the same model with the components library's `Menubar`, `MenubarMenu`, `MenubarTrigger`, `MenubarContent` and `MenubarItem`. `Keyboard.edit(tree, action)` dispatches undo, redo, cut, copy, paste and select-all to the focused control.

Native lifecycle tests are in `tests/Windows.hx`; build with the usual UI class paths and `-D ashui_window`, and run on a desktop display.

## File and folder dialogs

`FileDialog.open(app, options, complete)` presents an asynchronous macOS sheet on `app.window`. Options include `title`, `folder`, `directory` and file `extensions`. Completion runs in that window's UI context and receives the selected path, or null on cancellation. The returned function cancels a pending request; a window's disposal also cancels it. Dispose the request when replacing a workspace owner. Native callbacks only enqueue results and wake the platform loop; application code runs after the pump returns. Use `FileDialog.available()` before selecting this implementation on other platforms. `tests/FileDialogWindow.hx` is an isolated native smoke app for selection and cancellation.
