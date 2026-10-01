package ashui.layout;

/**
 * Matches blinc_layout::property::PropertyId exactly.
 * Implicitly cast to Int for the FFI boundary.
 */
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
}