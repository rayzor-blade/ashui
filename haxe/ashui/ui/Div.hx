package ashui.ui;

import ashui.layout.Element;
import ashui.layout.LayoutTree;
import ashui.layout.Node;
import ashui.layout.PropertyId;
import ashui.layout.IntoReactive;
import ashui.types.Brush;
import ashui.types.Color;
import ashui.types.CornerRadius;
import ashui.types.Style;

typedef DivAttributes = {
	// --- Tier 1: Visual Properties ---
	?bg:IntoReactive<Brush>,
	?borderColor:IntoReactive<Color>,
	?borderWidth:IntoReactive<Single>,
	?cornerRadius:IntoReactive<CornerRadius>,
	?opacity:IntoReactive<Single>,
	?color:IntoReactive<Color>,
	?accentColor:IntoReactive<Color>,

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
	public function new(?attr:DivAttributes, ?children:Array<Element>, tree:LayoutTree) {
		super(tree);

		// 1. Mint the native node arena in Rust
		var node = tree.createNode();
		this.node = node;

		// 2. Automatically bind all attributes dynamically using the unified node setter
		if (attr != null) {
			// Visuals
			if (attr.bg != null)
				node.set(Background, attr.bg);
			if (attr.borderColor != null)
				node.set(BorderColor, attr.borderColor);
			if (attr.borderWidth != null)
				node.set(BorderWidth, attr.borderWidth);
			if (attr.cornerRadius != null)
				node.set(CornerRadius, attr.cornerRadius);
			if (attr.opacity != null)
				node.set(Opacity, attr.opacity);
			if (attr.color != null)
				node.set(Color, attr.color);
			if (attr.accentColor != null)
				node.set(AccentColor, attr.accentColor);

			// Layout & Flexbox
			if (attr.width != null)
				node.set(Width, attr.width);
			if (attr.height != null)
				node.set(Height, attr.height);
			if (attr.minWidth != null)
				node.set(MinWidth, attr.minWidth);
			if (attr.maxWidth != null)
				node.set(MaxWidth, attr.maxWidth);
			if (attr.minHeight != null)
				node.set(MinHeight, attr.minHeight);
			if (attr.maxHeight != null)
				node.set(MaxHeight, attr.maxHeight);
			if (attr.padding != null)
				node.set(Padding, attr.padding);
			if (attr.margin != null)
				node.set(Margin, attr.margin);
			if (attr.gap != null)
				node.set(Gap, attr.gap);
			if (attr.flexDirection != null)
				node.set(FlexDirection, attr.flexDirection);
			if (attr.alignItems != null)
				node.set(AlignItems, attr.alignItems);
			if (attr.justifyContent != null)
				node.set(JustifyContent, attr.justifyContent);
			if (attr.alignSelf != null)
				node.set(AlignSelf, attr.alignSelf);
			if (attr.flexGrow != null)
				node.set(FlexGrow, attr.flexGrow);
			if (attr.flexShrink != null)
				node.set(FlexShrink, attr.flexShrink);
			if (attr.flexWrap != null)
				node.set(FlexWrap, attr.flexWrap);
			if (attr.flexBasis != null)
				node.set(FlexBasis, attr.flexBasis);
			if (attr.display != null)
				node.set(Display, attr.display);
			if (attr.overflow != null)
				node.set(Overflow, attr.overflow);
			if (attr.position != null)
				node.set(Position, attr.position);
			if (attr.top != null)
				node.set(Top, attr.top);
			if (attr.right != null)
				node.set(Right, attr.right);
			if (attr.bottom != null)
				node.set(Bottom, attr.bottom);
			if (attr.left != null)
				node.set(Left, attr.left);

			// Typography
			if (attr.fontSize != null)
				node.set(FontSize, attr.fontSize);
			if (attr.fontWeight != null)
				node.set(FontWeight, attr.fontWeight);
			if (attr.fontStyle != null)
				node.set(FontStyle, attr.fontStyle);
			if (attr.letterSpacing != null)
				node.set(LetterSpacing, attr.letterSpacing);
			if (attr.lineHeight != null)
				node.set(LineHeight, attr.lineHeight);
			if (attr.textAlign != null)
				node.set(TextAlign, attr.textAlign);
		}

		// 3. Mount children structure
		if (children != null) {
			for (child in children) {
				tree.addChild(node.id, child.node.id);
			}
		}
	}
}
