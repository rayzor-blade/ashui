package ashui.app;

#if (hlwindow || ashui_window)
import ashui.theme.ThemeBundle;
import window.ScaleSizing;
import window.Theme;
import window.WindowLevel;

/** `WindowConfig`'s fields: how a window opens, each optional. Sizes and positions are in logical pixels. **/
typedef WindowConfigData = {
	?title:String,
	/** The inner size; 800 by 600 when unset. **/
	?width:Int,
	?height:Int,
	/** The smallest and largest inner size it may be resized to. **/
	?minWidth:Int,
	?minHeight:Int,
	?maxWidth:Int,
	?maxHeight:Int,
	/** Where its outer top-left corner is on the desktop; the system's choice when unset. **/
	?x:Int,
	?y:Int,
	/** Steps its size moves in while resized. **/
	?resizeIncrementWidth:Int,
	?resizeIncrementHeight:Int,
	/** True by default. **/
	?resizable:Bool,
	?maximized:Bool,
	?fullscreen:Bool,
	/** Shown when it opens; true by default. **/
	?visible:Bool,
	/** Made the active window when it opens; true by default. **/
	?active:Bool,
	/** Its title bar and frame; true by default. **/
	?decorations:Bool,
	/** The title bar's buttons; each true by default. **/
	?closeButton:Bool,
	?minimizeButton:Bool,
	?maximizeButton:Bool,
	/** What is under it shows where the UI draws nothing: the page is not filled with the theme's background. **/
	?transparent:Bool,
	/** What is under a transparent window is blurred, where the platform can. **/
	?blur:Bool,
	/** Kept out of screenshots and screen sharing, where the platform can. **/
	?contentProtected:Bool,
	/** Above or below other windows, or among them. **/
	?level:WindowLevel,
	/** Its title bar and frame light or dark; the system's when unset. The UI's scheme follows it. **/
	?appearance:Theme,
	/** Whether `width`, `height` and the rest are logical pixels, the default, or physical ones. **/
	?scaleSizing:ScaleSizing,
	/** Its icon: RGBA pixels, `width` by `height`. **/
	?icon:{pixels:haxe.io.Bytes, width:Int, height:Int},
	/** The UI's theme, installed when none is; the default theme otherwise. **/
	?theme:ThemeBundle,
	/** Called after each presented frame with its number and the seconds since the window opened. **/
	?onFrame:(frame:Int, seconds:Float) -> Void
}

/**
	How `WindowedApp.run` opens its window, written either way: as an
	object,

	    WindowedApp.run({title: "ashui", width: 640, height: 480}, page);

	or built, each setter named as its field and returning the config:

	    WindowedApp.run(new WindowConfig().title("ashui").size(640, 480).transparent(true), page);

	An object given where a config is wanted is the config itself, so the
	builder carries on from one: `({title: "ashui"} : WindowConfig).size(640, 480)`.
	`data` reads the fields back.
**/
abstract WindowConfig(WindowConfigData) from WindowConfigData to WindowConfigData {
	/** An empty config: every field its default. **/
	public inline function new()
		this = {};

	/** The fields set. **/
	public var data(get, never):WindowConfigData;

	inline function get_data():WindowConfigData
		return this;

	public inline function title(value:String):WindowConfig {
		this.title = value;
		return abstract;
	}

	/** The inner size. **/
	public inline function size(width:Int, height:Int):WindowConfig {
		this.width = width;
		this.height = height;
		return abstract;
	}

	public inline function width(value:Int):WindowConfig {
		this.width = value;
		return abstract;
	}

	public inline function height(value:Int):WindowConfig {
		this.height = value;
		return abstract;
	}

	/** The smallest inner size it may be resized to. **/
	public inline function minSize(width:Int, height:Int):WindowConfig {
		this.minWidth = width;
		this.minHeight = height;
		return abstract;
	}

	/** The largest inner size it may be resized to. **/
	public inline function maxSize(width:Int, height:Int):WindowConfig {
		this.maxWidth = width;
		this.maxHeight = height;
		return abstract;
	}

	/** Where its outer top-left corner is on the desktop. **/
	public inline function position(x:Int, y:Int):WindowConfig {
		this.x = x;
		this.y = y;
		return abstract;
	}

	/** Steps its size moves in while resized. **/
	public inline function resizeIncrement(width:Int, height:Int):WindowConfig {
		this.resizeIncrementWidth = width;
		this.resizeIncrementHeight = height;
		return abstract;
	}

	public inline function resizable(value = true):WindowConfig {
		this.resizable = value;
		return abstract;
	}

	public inline function maximized(value = true):WindowConfig {
		this.maximized = value;
		return abstract;
	}

	public inline function fullscreen(value = true):WindowConfig {
		this.fullscreen = value;
		return abstract;
	}

	public inline function visible(value = true):WindowConfig {
		this.visible = value;
		return abstract;
	}

	public inline function active(value = true):WindowConfig {
		this.active = value;
		return abstract;
	}

	public inline function decorations(value = true):WindowConfig {
		this.decorations = value;
		return abstract;
	}

	/** Which of the title bar's buttons it has. **/
	public inline function buttons(close:Bool, minimize:Bool, maximize:Bool):WindowConfig {
		this.closeButton = close;
		this.minimizeButton = minimize;
		this.maximizeButton = maximize;
		return abstract;
	}

	public inline function transparent(value = true):WindowConfig {
		this.transparent = value;
		return abstract;
	}

	public inline function blur(value = true):WindowConfig {
		this.blur = value;
		return abstract;
	}

	public inline function contentProtected(value = true):WindowConfig {
		this.contentProtected = value;
		return abstract;
	}

	public inline function level(value:WindowLevel):WindowConfig {
		this.level = value;
		return abstract;
	}

	public inline function appearance(value:Theme):WindowConfig {
		this.appearance = value;
		return abstract;
	}

	public inline function scaleSizing(value:ScaleSizing):WindowConfig {
		this.scaleSizing = value;
		return abstract;
	}

	/** Its icon, RGBA pixels `width` by `height`. **/
	public inline function icon(pixels:haxe.io.Bytes, width:Int, height:Int):WindowConfig {
		this.icon = {pixels: pixels, width: width, height: height};
		return abstract;
	}

	public inline function theme(value:ThemeBundle):WindowConfig {
		this.theme = value;
		return abstract;
	}

	public inline function onFrame(value:(frame:Int, seconds:Float) -> Void):WindowConfig {
		this.onFrame = value;
		return abstract;
	}

	/** hlwindow's attributes for these fields; those unset are left to it. **/
	public function attributes():window.WindowAttributes {
		var c = this;
		var a = new window.WindowAttributes();
		a.title(c.title != null ? c.title : "ashui");
		a.width(c.width != null ? c.width : 800);
		a.height(c.height != null ? c.height : 600);
		a.resizable(c.resizable != false);
		if (c.minWidth != null) a.minWidth(c.minWidth);
		if (c.minHeight != null) a.minHeight(c.minHeight);
		if (c.maxWidth != null) a.maxWidth(c.maxWidth);
		if (c.maxHeight != null) a.maxHeight(c.maxHeight);
		if (c.x != null) a.x(c.x);
		if (c.y != null) a.y(c.y);
		if (c.resizeIncrementWidth != null) a.resizeIncrementWidth(c.resizeIncrementWidth);
		if (c.resizeIncrementHeight != null) a.resizeIncrementHeight(c.resizeIncrementHeight);
		if (c.maximized != null) a.maximized(c.maximized);
		if (c.fullscreen != null) a.fullscreen(c.fullscreen);
		if (c.visible != null) a.visible(c.visible);
		if (c.active != null) a.active(c.active);
		if (c.decorations != null) a.decorations(c.decorations);
		if (c.closeButton != null) a.closeButton(c.closeButton);
		if (c.minimizeButton != null) a.minimizeButton(c.minimizeButton);
		if (c.maximizeButton != null) a.maximizeButton(c.maximizeButton);
		if (c.transparent != null) a.transparent(c.transparent);
		if (c.blur != null) a.blur(c.blur);
		if (c.contentProtected != null) a.contentProtected(c.contentProtected);
		if (c.level != null) a.windowLevel(c.level);
		if (c.appearance != null) a.theme(c.appearance);
		if (c.scaleSizing != null) a.scaleSizing(c.scaleSizing);
		if (c.icon != null) {
			a.icon(c.icon.pixels);
			a.iconWidth(c.icon.width);
			a.iconHeight(c.icon.height);
		}
		return a;
	}
}
#end
