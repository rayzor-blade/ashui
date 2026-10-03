package ashui.ui;

import ashui.layout.Element;
import ashui.layout.LayoutTree;
import ashui.layout.Node;
import ashui.layout.Prop;
import ashui.layout.IntoReactive;
import ashui.types.Brush;
import ashui.types.Color;
import ashui.types.CornerRadius;
import ashui.types.Style;

typedef DivAttributes = {
	/** Applied before the other attributes, which win over it. **/
	?style:ashui.style.Style,
	// --- Tier 1: Visual Properties ---
	?bg:IntoReactive<Brush>,
	?borderColor:IntoReactive<Color>,
	?borderWidth:IntoReactive<Single>,
	?cornerRadius:IntoReactive<CornerRadius>,
	?cornerShape:IntoReactive<ashui.types.CornerShape>,
	?opacity:IntoReactive<Single>,
	?color:IntoReactive<Color>,
	?accentColor:IntoReactive<Color>,
	/** The shape it and everything inside it are clipped to; see `ClipPath`. **/
	?clipPath:IntoReactive<ashui.types.ClipPath>,

	// --- Tier 2: Layout & Flexbox Properties ---
	?width:IntoReactive<Single>,
	?height:IntoReactive<Single>,
	?minWidth:IntoReactive<Single>,
	?maxWidth:IntoReactive<Single>,
	?minHeight:IntoReactive<Single>,
	?maxHeight:IntoReactive<Single>,
	?padding:IntoReactive<Single>,
	?margin:IntoReactive<Single>,
	?gap:IntoReactive<Single>,
	?flexDirection:IntoReactive<FlexDirection>,
	?alignItems:IntoReactive<Align>,
	?justifyContent:IntoReactive<Justify>,
	?alignSelf:IntoReactive<Align>,
	?flexGrow:IntoReactive<Single>,
	?flexShrink:IntoReactive<Single>,
	?flexWrap:IntoReactive<FlexWrap>,
	?flexBasis:IntoReactive<Single>,
	?display:IntoReactive<Display>,
	?overflow:IntoReactive<Overflow>,
	?position:IntoReactive<Position>,
	?top:IntoReactive<Single>,
	?right:IntoReactive<Single>,
	?bottom:IntoReactive<Single>,
	?left:IntoReactive<Single>,

	// --- Text Measurement & Typography Properties ---
	?fontSize:IntoReactive<Single>,
	?fontWeight:IntoReactive<FontWeight>,
	?fontStyle:IntoReactive<FontStyle>,
	?letterSpacing:IntoReactive<Single>,
	?lineHeight:IntoReactive<Single>,
	?textAlign:IntoReactive<TextAlign>
}

class Div extends Element {
	public function new(?attr:DivAttributes, ?children:Array<Element>, ?tree:LayoutTree) {
		super(tree);

		// 1. Mint the native node arena in Rust
		var node = this.tree.createNode();
		this.node = node;

		// 2. Automatically bind all attributes dynamically using the unified node setter
		if (attr != null) {
			if (attr.style != null)
				attr.style.apply(node);
			// Visuals
			if (attr.bg != null)
				node.set(Prop.Background, attr.bg);
			if (attr.borderColor != null)
				node.set(Prop.BorderColor, attr.borderColor);
			if (attr.borderWidth != null)
				node.set(Prop.BorderWidth, attr.borderWidth);
			if (attr.cornerRadius != null)
				node.set(Prop.CornerRadius, attr.cornerRadius);
			if (attr.cornerShape != null)
				node.set(Prop.CornerShape, attr.cornerShape);
			if (attr.opacity != null)
				node.set(Prop.Opacity, attr.opacity);
			if (attr.color != null)
				node.set(Prop.Color, attr.color);
			if (attr.clipPath != null)
				node.set(Prop.ClipPath, attr.clipPath);
			if (attr.accentColor != null)
				node.set(Prop.AccentColor, attr.accentColor);

			// Layout & Flexbox
			if (attr.width != null)
				node.set(Prop.Width, attr.width);
			if (attr.height != null)
				node.set(Prop.Height, attr.height);
			if (attr.minWidth != null)
				node.set(Prop.MinWidth, attr.minWidth);
			if (attr.maxWidth != null)
				node.set(Prop.MaxWidth, attr.maxWidth);
			if (attr.minHeight != null)
				node.set(Prop.MinHeight, attr.minHeight);
			if (attr.maxHeight != null)
				node.set(Prop.MaxHeight, attr.maxHeight);
			if (attr.padding != null)
				node.set(Prop.Padding, attr.padding);
			if (attr.margin != null)
				node.set(Prop.Margin, attr.margin);
			if (attr.gap != null)
				node.set(Prop.Gap, attr.gap);
			if (attr.flexDirection != null)
				node.set(Prop.FlexDirection, attr.flexDirection);
			if (attr.alignItems != null)
				node.set(Prop.AlignItems, attr.alignItems);
			if (attr.justifyContent != null)
				node.set(Prop.JustifyContent, attr.justifyContent);
			if (attr.alignSelf != null)
				node.set(Prop.AlignSelf, attr.alignSelf);
			if (attr.flexGrow != null)
				node.set(Prop.FlexGrow, attr.flexGrow);
			if (attr.flexShrink != null)
				node.set(Prop.FlexShrink, attr.flexShrink);
			if (attr.flexWrap != null)
				node.set(Prop.FlexWrap, attr.flexWrap);
			if (attr.flexBasis != null)
				node.set(Prop.FlexBasis, attr.flexBasis);
			if (attr.display != null)
				node.set(Prop.Display, attr.display);
			if (attr.overflow != null)
				node.set(Prop.Overflow, attr.overflow);
			if (attr.position != null)
				node.set(Prop.Position, attr.position);
			if (attr.top != null)
				node.set(Prop.Top, attr.top);
			if (attr.right != null)
				node.set(Prop.Right, attr.right);
			if (attr.bottom != null)
				node.set(Prop.Bottom, attr.bottom);
			if (attr.left != null)
				node.set(Prop.Left, attr.left);

			// Typography
			if (attr.fontSize != null)
				node.set(Prop.FontSize, attr.fontSize);
			if (attr.fontWeight != null)
				node.set(Prop.FontWeight, attr.fontWeight);
			if (attr.fontStyle != null)
				node.set(Prop.FontStyle, attr.fontStyle);
			if (attr.letterSpacing != null)
				node.set(Prop.LetterSpacing, attr.letterSpacing);
			if (attr.lineHeight != null)
				node.set(Prop.LineHeight, attr.lineHeight);
			if (attr.textAlign != null)
				node.set(Prop.TextAlign, attr.textAlign);
		}

		// 3. Mount children structure
		if (children != null) {
			for (child in children) {
				this.tree.addChild(node.id, child.node.id);
			}
		}
	}
}
