package ashui.layout;

/**
	A property key that carries the type of its value, so `Node.set` rejects
	`set(Prop.Width, Brush.solid(0xff0000))` at compile time. Each key is the
	`PropertyId` it stands for.

	`Filter` and `Compound` have no key: nothing applies them yet.
**/
abstract Prop<T>(PropertyId) to PropertyId {
	// --- visual ---
	public static inline var Background:Prop<ashui.types.Brush> = cast PropertyId.Background;
	public static inline var BorderColor:Prop<ashui.types.Color> = cast PropertyId.BorderColor;
	public static inline var BorderWidth:Prop<Single> = cast PropertyId.BorderWidth;
	/** One side's border width, over `BorderWidth`; the colour stays `BorderColor`. **/
	public static inline var BorderTopWidth:Prop<Single> = cast PropertyId.BorderTopWidth;
	public static inline var BorderRightWidth:Prop<Single> = cast PropertyId.BorderRightWidth;
	public static inline var BorderBottomWidth:Prop<Single> = cast PropertyId.BorderBottomWidth;
	public static inline var BorderLeftWidth:Prop<Single> = cast PropertyId.BorderLeftWidth;
	/** A ring outside the border box, `OutlineOffset` away from it, its corners following the box's. **/
	public static inline var OutlineWidth:Prop<Single> = cast PropertyId.OutlineWidth;
	public static inline var OutlineOffset:Prop<Single> = cast PropertyId.OutlineOffset;
	public static inline var OutlineColor:Prop<ashui.types.Color> = cast PropertyId.OutlineColor;
	public static inline var CornerRadius:Prop<ashui.types.CornerRadius> = cast PropertyId.CornerRadius;
	/** Shares its id with `CornerRadius`; the two are told apart by value. **/
	public static inline var CornerShape:Prop<ashui.types.CornerShape> = cast PropertyId.CornerRadius;
	public static inline var Opacity:Prop<Single> = cast PropertyId.Opacity;
	public static inline var Transform:Prop<ashui.types.Transform> = cast PropertyId.Transform;
	public static inline var Shadow:Prop<ashui.types.Shadow> = cast PropertyId.Shadow;
	public static inline var Color:Prop<ashui.types.Color> = cast PropertyId.Color;
	public static inline var AccentColor:Prop<ashui.types.Color> = cast PropertyId.AccentColor;

	// --- layout ---
	public static inline var Width:Prop<Single> = cast PropertyId.Width;
	public static inline var Height:Prop<Single> = cast PropertyId.Height;
	public static inline var MinWidth:Prop<Single> = cast PropertyId.MinWidth;
	public static inline var MaxWidth:Prop<Single> = cast PropertyId.MaxWidth;
	public static inline var MinHeight:Prop<Single> = cast PropertyId.MinHeight;
	public static inline var MaxHeight:Prop<Single> = cast PropertyId.MaxHeight;
	public static inline var Padding:Prop<Single> = cast PropertyId.Padding;
	public static inline var Margin:Prop<Single> = cast PropertyId.Margin;
	public static inline var Gap:Prop<Single> = cast PropertyId.Gap;
	public static inline var FlexDirection:Prop<ashui.types.Style.FlexDirection> = cast PropertyId.FlexDirection;
	public static inline var AlignItems:Prop<ashui.types.Style.Align> = cast PropertyId.AlignItems;
	public static inline var JustifyContent:Prop<ashui.types.Style.Justify> = cast PropertyId.JustifyContent;
	public static inline var AlignSelf:Prop<ashui.types.Style.Align> = cast PropertyId.AlignSelf;
	public static inline var FlexGrow:Prop<Single> = cast PropertyId.FlexGrow;
	public static inline var FlexShrink:Prop<Single> = cast PropertyId.FlexShrink;
	public static inline var FlexWrap:Prop<ashui.types.Style.FlexWrap> = cast PropertyId.FlexWrap;
	public static inline var FlexBasis:Prop<Single> = cast PropertyId.FlexBasis;
	public static inline var Display:Prop<ashui.types.Style.Display> = cast PropertyId.Display;
	public static inline var Overflow:Prop<ashui.types.Style.Overflow> = cast PropertyId.Overflow;
	public static inline var Position:Prop<ashui.types.Style.Position> = cast PropertyId.Position;
	public static inline var Top:Prop<Single> = cast PropertyId.Top;
	public static inline var Right:Prop<Single> = cast PropertyId.Right;
	public static inline var Bottom:Prop<Single> = cast PropertyId.Bottom;
	public static inline var Left:Prop<Single> = cast PropertyId.Left;

	// --- one side, or a fraction of the parent ---
	// A margin, size or inset of NaN is `auto`.
	public static inline var PaddingTop:Prop<Single> = cast PropertyId.PaddingTop;
	public static inline var PaddingRight:Prop<Single> = cast PropertyId.PaddingRight;
	public static inline var PaddingBottom:Prop<Single> = cast PropertyId.PaddingBottom;
	public static inline var PaddingLeft:Prop<Single> = cast PropertyId.PaddingLeft;
	public static inline var MarginTop:Prop<Single> = cast PropertyId.MarginTop;
	public static inline var MarginRight:Prop<Single> = cast PropertyId.MarginRight;
	public static inline var MarginBottom:Prop<Single> = cast PropertyId.MarginBottom;
	public static inline var MarginLeft:Prop<Single> = cast PropertyId.MarginLeft;
	/** The gap between columns. **/
	public static inline var GapX:Prop<Single> = cast PropertyId.GapX;
	/** The gap between rows. **/
	public static inline var GapY:Prop<Single> = cast PropertyId.GapY;
	/** A fraction of the parent's width, 0 to 1. **/
	public static inline var WidthPercent:Prop<Single> = cast PropertyId.WidthPercent;
	public static inline var HeightPercent:Prop<Single> = cast PropertyId.HeightPercent;
	public static inline var MinWidthPercent:Prop<Single> = cast PropertyId.MinWidthPercent;
	public static inline var MaxWidthPercent:Prop<Single> = cast PropertyId.MaxWidthPercent;
	public static inline var MinHeightPercent:Prop<Single> = cast PropertyId.MinHeightPercent;
	public static inline var MaxHeightPercent:Prop<Single> = cast PropertyId.MaxHeightPercent;
	public static inline var FlexBasisPercent:Prop<Single> = cast PropertyId.FlexBasisPercent;

	// --- text ---
	public static inline var FontSize:Prop<Single> = cast PropertyId.FontSize;
	public static inline var FontFamily:Prop<String> = cast PropertyId.FontFamily;
	public static inline var FontWeight:Prop<ashui.types.Style.FontWeight> = cast PropertyId.FontWeight;
	public static inline var FontStyle:Prop<ashui.types.Style.FontStyle> = cast PropertyId.FontStyle;
	public static inline var LetterSpacing:Prop<Single> = cast PropertyId.LetterSpacing;
	public static inline var LineHeight:Prop<Single> = cast PropertyId.LineHeight;
	public static inline var TextAlign:Prop<ashui.types.Style.TextAlign> = cast PropertyId.TextAlign;
	public static inline var TextContent:Prop<String> = cast PropertyId.TextContent;
}
