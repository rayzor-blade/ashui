package ashui.ui;

#if ashui_gpu
import ashui.core.render.SurfaceTexture;
import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.reactive.Owner;
import ashui.reactive.Watch;
import ashui.types.ObjectFit;
import ashui.types.PixelSurface;

typedef SurfaceProps = {
	/** The pixels to draw. **/
	source:PixelSurface,
	/** How they sit in the box: `Contain` by default; `Cover`, `Fill`, `None` and `ScaleDown` as for an image. **/
	?fit:IntoReactive<ObjectFit>,
	?id:String
}

/**
	A `PixelSurface` drawn in layout, written as `<surface>` in HXX.

	It sizes, clips and takes opacity, transforms and CSS as any box does.
	The surface's pixels are uploaded to the GPU only for the rectangle each
	frame changed, and not at all when nothing was written; a write asks for
	a frame by itself.

	```haxe
	var screen = new PixelSurface(1280, 720);
	<surface source={screen} fit={Contain} class="w-full h-full" />
	```
**/
class Surface extends Component<SurfaceProps> {
	/** What uploads the pixels and draws them. **/
	public var texture(default, null):SurfaceTexture;

	function render():Element {
		texture = new SurfaceTexture(props.source);
		var drawn = texture;
		Owner.onCleanup(drawn.dispose);
		function fit():ObjectFit
			return props.fit == null ? ObjectFit.Contain : switch props.fit {
				case Const(v): v;
				case Bound(s): s.get();
				case Derived(c): c.get();
			};
		var canvas = new Canvas({id: props.id, paint: frame -> texture.paint(frame, fit())});
		var source = props.source;
		new Watch(() -> source.changed.get(), _ -> canvas.repaint());
		if (props.fit != null)
			new Watch(() -> fit(), _ -> canvas.repaint());
		return canvas;
	}
}
#end
