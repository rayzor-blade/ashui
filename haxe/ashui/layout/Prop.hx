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
	public static inline var CornerRadius:Prop<ashui.types.CornerRadius> = cast PropertyId.CornerRadius;
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
