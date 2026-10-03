package ashui.layout;

/**
	The kind of value a property takes, which decides how `Node` passes it
	to the native side: a float, an int (enums included), a style value of
	one of the listed types, or a string.
**/
enum abstract PropertyDataType(Int) {
    var TypeF32;
    var TypeI32;
    var TypeBrush;
    var TypeColor;
    var TypeCornerRadius;
    var TypeTransform;
    var TypeShadow;
    var TypeString;
    var TypeClipPath;
}

/**
	The number that names a node property where Haxe calls native code.
	Code sets properties through `Prop`, whose keys carry their value's type;
	`PropertyId` is the untyped id behind each key, an `Int` as the native
	functions take it. The ids up to `Compound` must match Blinc's
	`PropertyId` exactly; ashui's own come after.
**/
enum abstract PropertyId(Int) from Int to Int {
    // --- visual-only (Tier 1) ---
    var Background = 0;
    var BorderColor = 1;
    var BorderWidth = 2;
    var CornerRadius = 3;
    var Opacity = 4;
    var Transform = 5;
    var Shadow = 6;
    var Color = 7;
    var Filter = 8;
    var AccentColor = 9;

    // --- layout-affecting (Tier 2) ---
    var Width = 10;
    var Height = 11;
    var MinWidth = 12;
    var MaxWidth = 13;
    var MinHeight = 14;
    var MaxHeight = 15;
    var Padding = 16;
    var Margin = 17;
    var Gap = 18;
    var FlexDirection = 19;
    var AlignItems = 20;
    var JustifyContent = 21;
    var AlignSelf = 22;
    var FlexGrow = 23;
    var FlexShrink = 24;
    var FlexWrap = 25;
    var FlexBasis = 26;
    var Display = 27;
    var Overflow = 28;
    var Position = 29;
    var Top = 30;
    var Right = 31;
    var Bottom = 32;
    var Left = 33;

    // --- text-measurement affecting ---
    var FontSize = 34;
    var FontFamily = 35;
    var FontWeight = 36;
    var FontStyle = 37;
    var LetterSpacing = 38;
    var LineHeight = 39;
    var TextAlign = 40;
    var TextContent = 41;

    var Compound = 42;
    // --- ashui's own, after Blinc's: one side of the spacing, or a size as a fraction (0 to 1) of the parent's ---
    var PaddingTop = 43;
    var PaddingRight = 44;
    var PaddingBottom = 45;
    var PaddingLeft = 46;
    var MarginTop = 47;
    var MarginRight = 48;
    var MarginBottom = 49;
    var MarginLeft = 50;
    var GapX = 51;
    var GapY = 52;
    var WidthPercent = 53;
    var HeightPercent = 54;
    var MinWidthPercent = 55;
    var MaxWidthPercent = 56;
    var MinHeightPercent = 57;
    var MaxHeightPercent = 58;
    var FlexBasisPercent = 59;
    // One side's border width over BorderWidth; the colour is BorderColor's.
    var BorderTopWidth = 60;
    var BorderRightWidth = 61;
    var BorderBottomWidth = 62;
    var BorderLeftWidth = 63;
    // An outline outside the border box: its width, its distance from the box, its colour.
    var OutlineWidth = 64;
    var OutlineOffset = 65;
    var OutlineColor = 66;
    // One side's border colour over BorderColor.
    var BorderTopColor = 67;
    var BorderRightColor = 68;
    var BorderBottomColor = 69;
    var BorderLeftColor = 70;
    // How far in from a side a box that clips its children fades them out.
    var FadeTop = 71;
    var FadeRight = 72;
    var FadeBottom = 73;
    var FadeLeft = 74;
    // A CSS clip-path: the shape the element and everything inside it are clipped to.
    var ClipPath = 75;
    // CSS colour filters, each an amount over the identity: 1 for brightness, contrast and saturate, 0 for the rest.
    var FilterBrightness = 76;
    var FilterContrast = 77;
    var FilterGrayscale = 78;
    var FilterHueRotate = 79;
    var FilterInvert = 80;
    var FilterSaturate = 81;
    var FilterSepia = 82;
    // CSS's blur(): the Gaussian's standard deviation, in layout units.
    var FilterBlur = 83;
    // CSS's drop-shadow(): a Shadow's first layer, cast by the element's shape, not its box.
    var DropShadow = 84;
    // CSS grid, as CSS text: a grid's tracks, and an item's lines.
    var GridTemplateColumns = 85;
    var GridTemplateRows = 86;
    var GridColumn = 87;
    var GridRow = 88;

    /** The kind of value this property takes, which `Node.set` dispatches on. **/
    public inline function getDataType(): PropertyDataType {
        return switch (this) {
            case Background: TypeBrush;
            case BorderColor | Color | AccentColor | OutlineColor | BorderTopColor | BorderRightColor | BorderBottomColor | BorderLeftColor: TypeColor;
            case CornerRadius: TypeCornerRadius;

            case Transform: TypeTransform;
            case Shadow: TypeShadow;
            case ClipPath: TypeClipPath;
            case DropShadow: TypeShadow;

            // Strings (Typography / Paths / Content)
            case FontFamily | TextContent | GridTemplateColumns | GridTemplateRows | GridColumn | GridRow: TypeString;
            
            // Floats (Dimensions, Spacing, Opacity, Strokes, Typography metrics)
            case Width | Height | MinWidth | MaxWidth | MinHeight | MaxHeight |
                 Padding | Margin | Gap | FlexBasis | FlexGrow | FlexShrink |
                 Top | Right | Bottom | Left | Opacity | BorderWidth |
                 FontSize | LetterSpacing | LineHeight | PaddingTop | PaddingRight | PaddingBottom | PaddingLeft | MarginTop | MarginRight | MarginBottom | MarginLeft | GapX | GapY | WidthPercent | HeightPercent | MinWidthPercent | MaxWidthPercent | MinHeightPercent | MaxHeightPercent | FlexBasisPercent | BorderTopWidth | BorderRightWidth | BorderBottomWidth | BorderLeftWidth | OutlineWidth | OutlineOffset | FadeTop | FadeRight | FadeBottom | FadeLeft | FilterBrightness | FilterContrast | FilterGrayscale | FilterHueRotate | FilterInvert | FilterSaturate | FilterSepia | FilterBlur:
                TypeF32;

            // Integers / Enums (Flexbox alignments, wraps, displays, weights, styles)
            case FlexDirection | AlignItems | JustifyContent | AlignSelf |
                 FlexWrap | Display | Overflow | Position |
                 FontWeight | FontStyle | TextAlign | Filter | Compound:
                TypeI32;

            default:
                TypeI32; // Enums, FlexDirections, Alignments, etc.
        }
    }

    /**
        Whether this is one of the core layout properties, `Width` to `Left`,
        which move or resize nodes rather than only change how they are
        drawn. ashui's own per-side and percentage properties are not
        counted.
    **/
    public inline function isLayoutAffecting(): Bool {
        // Everything from Width (10) to Left (33) affects layout geometry
        return this >= 10 && this <= 33;
    }
}