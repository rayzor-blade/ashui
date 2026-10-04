import ashui.core.render.Snapshot;
import ashui.css.Css;
import ashui.layout.Element;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Bitmap;
import ashui.types.Style;
import ashui.ui.Div;

/**
	Images styled from a stylesheet alone, after Blinc's image_css_demo: the
	Haxe gives each image card an id, the CSS does the rest. Opacity,
	corner radius, borders, shadows, transforms, hover transitions (in a
	window), a `url()` background, filters, gradient masks and mask
	transitions. Writes `.ashui/snapshots/image-css.png`; `--window` to
	hover.
**/
class ImageCssDemo {
	static final STYLESHEET = '
		#root { padding: 32px; gap: 28px; flex-direction: column; }
		.title { font-size: 28px; font-weight: 700; color: var(--text-primary); }
		.subtitle { font-size: 15px; color: var(--text-secondary); }
		.section { flex-direction: column; gap: 12px; }
		.section-title { font-size: 18px; font-weight: 600; color: var(--text-primary); }
		.row { flex-direction: row; gap: 20px; align-items: flex-end; flex-wrap: wrap; }
		.card { flex-direction: column; gap: 6px; align-items: center; }
		.frame { width: 100px; height: 100px; overflow: hidden; }
		.label { font-size: 12px; font-weight: 600; color: var(--text-secondary); }

		/* 1. Opacity */
		#img-opacity-100 { opacity: 1.0; border-radius: 8px; }
		#img-opacity-75 { opacity: 0.75; border-radius: 8px; }
		#img-opacity-50 { opacity: 0.5; border-radius: 8px; }
		#img-opacity-25 { opacity: 0.25; border-radius: 8px; }

		/* 2. Border radius */
		#img-radius-0 { border-radius: 0px; }
		#img-radius-12 { border-radius: 12px; }
		#img-radius-24 { border-radius: 24px; }
		#img-radius-circle { border-radius: 50px; }

		/* 3. Border */
		#img-border-thin { border-radius: 12px; border-width: 2px; border-color: rgba(255, 255, 255, 0.6); }
		#img-border-thick { border-radius: 12px; border-width: 4px; border-color: #3b82f6; }
		#img-border-accent { border-radius: 50px; border-width: 3px; border-color: #f59e0b; }

		/* 4. Box shadow */
		#img-shadow-sm { border-radius: 12px; box-shadow: 0 2px 8px rgba(0, 0, 0, 0.4); }
		#img-shadow-md { border-radius: 12px; box-shadow: 0 4px 16px rgba(59, 130, 246, 0.5); }
		#img-shadow-lg { border-radius: 12px; box-shadow: 0 8px 32px rgba(245, 158, 11, 0.6); }

		/* 5. Transforms */
		#img-rotate { border-radius: 12px; transform: rotate(12deg); }
		#img-scale { border-radius: 12px; transform: scale(1.15); }
		#img-skew { border-radius: 12px; transform: skewX(-8deg); }

		/* 6. Hover transitions */
		#img-hover-scale { border-radius: 12px; transition: transform 0.25s ease, box-shadow 0.25s ease; box-shadow: 0 2px 8px rgba(0, 0, 0, 0.3); }
		#img-hover-scale:hover { transform: scale(1.08); box-shadow: 0 8px 24px rgba(59, 130, 246, 0.5); }
		#img-hover-opacity { border-radius: 12px; opacity: 0.6; transition: opacity 0.3s ease, border-color 0.3s ease; border-width: 2px; border-color: rgba(255, 255, 255, 0.2); }
		#img-hover-opacity:hover { opacity: 1.0; border-color: rgba(255, 255, 255, 0.8); }
		#img-hover-rotate { border-radius: 50px; transition: transform 0.4s ease, box-shadow 0.3s ease; border-width: 2px; border-color: rgba(245, 158, 11, 0.6); }
		#img-hover-rotate:hover { transform: rotate(15deg) scale(1.15); box-shadow: 0 8px 24px rgba(245, 158, 11, 0.5); }
		#img-hover-shadow { border-radius: 12px; transition: box-shadow 0.3s ease; box-shadow: 0 0px 0px rgba(0, 0, 0, 0.0); }
		#img-hover-shadow:hover { box-shadow: 0 0px 40px rgba(139, 92, 246, 0.7); }

		/* 7. Background image */
		#bg-image-card {
			width: 100px; height: 100px; border-radius: 16px;
			background: url("../assets/avatar.jpg"); background-size: cover;
			box-shadow: 0 4px 16px rgba(0, 0, 0, 0.4); border-width: 2px; border-color: rgba(255, 255, 255, 0.3);
			transition: transform 0.25s ease, box-shadow 0.25s ease;
		}
		#bg-image-card:hover { transform: scale(1.05); box-shadow: 0 8px 24px rgba(59, 130, 246, 0.5); }

		/* 8. Filters */
		#img-grayscale { border-radius: 12px; filter: grayscale(100%); }
		#img-sepia { border-radius: 12px; filter: sepia(100%); }
		#img-invert { border-radius: 12px; filter: invert(100%); }
		#img-brightness { border-radius: 12px; filter: brightness(150%); }
		#img-contrast { border-radius: 12px; filter: contrast(200%); }
		#img-saturate { border-radius: 12px; filter: saturate(300%); }
		#img-hue-rotate { border-radius: 12px; filter: hue-rotate(90deg); }
		#img-filter-combo { border-radius: 12px; filter: grayscale(50%) brightness(120%) contrast(110%); }

		/* 9. Masks */
		#img-mask-fade-bottom { border-radius: 12px; mask-image: linear-gradient(to bottom, black, transparent); }
		#img-mask-fade-right { border-radius: 12px; mask-image: linear-gradient(to right, black, transparent); }
		#img-mask-radial { border-radius: 12px; mask-image: radial-gradient(circle, black, transparent); }
		#img-mask-diagonal { border-radius: 12px; mask-image: linear-gradient(135deg, black 0%, transparent 100%); }

		/* 10. Mask transitions */
		#img-mask-hover-reveal { border-radius: 12px; mask-image: linear-gradient(to bottom, black, transparent); transition: mask-image 0.6s ease; }
		#img-mask-hover-reveal:hover { mask-image: linear-gradient(to bottom, black, black); }
		#img-mask-hover-radial { border-radius: 12px; mask-image: radial-gradient(circle, black, transparent); transition: mask-image 0.5s ease; }
		#img-mask-hover-radial:hover { mask-image: radial-gradient(circle, black, black); }
		#img-mask-hover-fade { border-radius: 12px; mask-image: linear-gradient(to right, black, black); transition: mask-image 0.5s ease; }
		#img-mask-hover-fade:hover { mask-image: linear-gradient(to right, black, transparent); }
	';

	static var avatar:Bitmap;

	/** An image card: the framed image, which the stylesheet styles by `id`, and its label. **/
	static function card(id:String, label:String):Element {
		var frame = new Div({id: id, classes: ["frame"]}, [<img src={avatar} class="object-cover" width={100} height={100} />]);
		ashui.input.Interaction.of(frame.node);
		return new Div({classes: ["card"]}, [frame, styled("label", label)]);
	}

	static function section(title:String, cards:Array<Element>):Element
		return new Div({classes: ["section"]}, [styled("section-title", title), new Div({classes: ["row"]}, cards)]);

	/** Text under a class of this page's stylesheet, which its text inherits. **/
	static function styled(cls:String, text:String):Element
		return new Div({classes: [cls]}, [new ashui.ui.Text(text)]);

	static function main() {
		var light = Sys.getEnv("SCHEME") == "light";
		ThemeState.init(DefaultTheme.bundle(), light ? Light : Dark);
		var page = ThemeState.get().color(Background);
		avatar = Bitmap.embed("assets/avatar.jpg");
		Css.load(STYLESHEET);
		var build = () -> new Div({id: "root", width: 1100}, [
			new Div({flexDirection: FlexDirection.Column, gap: 4}, [
				styled("title", "Image CSS Styling Demo"),
				styled("subtitle", "All visual styles applied from a stylesheet; the Haxe only defines structure")
			]),
			section("1. Opacity", [card("img-opacity-100", "opacity: 1.0"), card("img-opacity-75", "opacity: 0.75"), card("img-opacity-50", "opacity: 0.50"), card("img-opacity-25", "opacity: 0.25")]),
			section("2. Border Radius", [card("img-radius-0", "0px"), card("img-radius-12", "12px"), card("img-radius-24", "24px"), card("img-radius-circle", "50px (circle)")]),
			section("3. Border", [card("img-border-thin", "2px white"), card("img-border-thick", "4px blue"), card("img-border-accent", "3px amber circle")]),
			section("4. Box Shadow", [card("img-shadow-sm", "small"), card("img-shadow-md", "medium (blue)"), card("img-shadow-lg", "large (amber)")]),
			section("5. CSS Transform", [card("img-rotate", "rotate(12deg)"), card("img-scale", "scale(1.15)"), card("img-skew", "skewX(-8deg)")]),
			section("6. Hover Transitions (hover over images)", [card("img-hover-scale", "scale + shadow"), card("img-hover-opacity", "opacity + border"), card("img-hover-rotate", "rotate + scale"), card("img-hover-shadow", "glow shadow")]),
			section("7. Background Image (CSS url())", [new Div({classes: ["card"]}, [new Div({id: "bg-image-card"}), styled("label", "background: url(...)")])]),
			section("8. CSS Filters", [card("img-grayscale", "grayscale(100%)"), card("img-sepia", "sepia(100%)"), card("img-invert", "invert(100%)"), card("img-brightness", "brightness(150%)"), card("img-contrast", "contrast(200%)"), card("img-saturate", "saturate(300%)"), card("img-hue-rotate", "hue-rotate(90deg)"), card("img-filter-combo", "combo")]),
			section("9. Mask Image (CSS Gradients)", [card("img-mask-fade-bottom", "fade bottom"), card("img-mask-fade-right", "fade right"), card("img-mask-radial", "radial reveal"), card("img-mask-diagonal", "diagonal")]),
			section("10. Mask Transitions (Hover)", [card("img-mask-hover-reveal", "reveal down"), card("img-mask-hover-radial", "radial in"), card("img-mask-hover-fade", "fade right")])
		]);
		Snapshot.scene(light ? "image-css-light" : "image-css", 1100, 1960, build, page.rgb(), page.a, 2.0, 1.0);
	}
}
