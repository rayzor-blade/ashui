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

/** Optional layout, styling, and input attributes for `Div`. See `Prop` for the underlying node properties. **/
typedef DivAttributes = {
	/** CSS element name. Defaults to `div`; built-in elements use names such as `h1`, `p`, and `button`. **/
	?tag:String,
	/** Element ID, selected by `#id` in CSS. **/
	?id:String,
	/** CSS class names. Signals and computeds update the class list reactively. **/
	?classes:IntoReactive<Array<String>>,
	/** Base style. Explicit attributes override properties set by this style. **/
	?style:ashui.style.Style,
	// --- Tier 1: Visual Properties ---
	?bg:IntoReactive<Brush>,
	?borderColor:IntoReactive<Color>,
	?borderWidth:IntoReactive<Single>,
	?cornerRadius:IntoReactive<CornerRadius>,
	?cornerShape:IntoReactive<ashui.types.CornerShape>,
	?opacity:IntoReactive<Single>,
	?visibility:IntoReactive<Visibility>,
	?pointerEvents:IntoReactive<PointerEvents>,
	?color:IntoReactive<Color>,
	?accentColor:IntoReactive<Color>,
	/** Clips the element and its children to this shape. See `ClipPath`. **/
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
	/** Masks the element and its children with a gradient brush. The brush alpha controls visibility, as in CSS `mask-image`. **/
	?maskImage:IntoReactive<ashui.types.Brush>,
	/** Replaces the rounded box outline with a notch shape. Supports concave corners, steps, and edge modifiers; reactive values update the shape. **/
	?notch:IntoReactive<ashui.types.Notch>,
	/** Animates position and size changes caused by layout. See `ashui.animation.LayoutAnimation`. **/
	?animateLayout:Bool,
	/** CSS column tracks, such as `repeat(3, 1fr) 120px`. Requires grid display. **/
	?gridTemplateColumns:IntoReactive<String>,
	/** CSS row tracks for a grid container. **/
	?gridTemplateRows:IntoReactive<String>,
	/** Grid columns occupied by this child, such as `span 2` or `1 / -1`. **/
	?gridColumn:IntoReactive<String>,
	/** Grid rows occupied by this child, using CSS grid-line syntax. **/
	?gridRow:IntoReactive<String>,
	?display:IntoReactive<Display>,
	?overflow:IntoReactive<Overflow>,
	/** Releases pixels and atlas space for offscreen descendant images. Defaults to false. **/
	?virtualizeImages:Bool,
	?position:IntoReactive<Position>,
	?order:IntoReactive<Int>,
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
	?textAlign:IntoReactive<TextAlign>,
	// --- Input: bound to its `ashui.input.Interaction`, as hxx binds these attributes ---
	?onClick:ashui.input.Events.PointerEvent->Void,
	?onPointerDown:ashui.input.Events.PointerEvent->Void,
	?onPointerUp:ashui.input.Events.PointerEvent->Void,
	?onPointerMove:ashui.input.Events.PointerEvent->Void,
	?onPointerEnter:ashui.input.Events.PointerEvent->Void,
	?onPointerLeave:ashui.input.Events.PointerEvent->Void,
	?onWheel:ashui.input.Events.PointerEvent->Void,
	?onTouchStart:ashui.input.Events.TouchEvent->Void,
	?onTouchMove:ashui.input.Events.TouchEvent->Void,
	?onTouchEnd:ashui.input.Events.TouchEvent->Void,
	?onTouchCancel:ashui.input.Events.TouchEvent->Void,
	?onKeyDown:ashui.input.Events.KeyEvent->Void,
	?onKeyUp:ashui.input.Events.KeyEvent->Void,
	?onTextInput:ashui.input.Events.TextInputEvent->Void,
	?onComposition:ashui.input.Events.CompositionEvent->Void,
	?onFocus:ashui.input.Events.FocusEvent->Void,
	?onBlur:ashui.input.Events.FocusEvent->Void,
	/** Allows the element to receive focus through Tab or a pointer press. **/
	?focusable:Bool,
	/** Disables input and applies the CSS `:disabled` state. Accepts reactive values. **/
	?disabled:IntoReactive<Bool>
}

/**
	A container for arranging and styling child elements.

	Use `<div>` in HXX. The default layout is flexbox; CSS and attributes control
	spacing, sizing, appearance, and input handlers. Attributes typed
	`IntoReactive<T>` accept constants, signals, or computeds.
**/
class Div extends Element {
	/** Applies a notch shape and tracks reactive changes. Clears the shape when the current owner is disposed. **/
	public static function bindNotch(div:Div, notch:IntoReactive<ashui.types.Notch>):Void {
		var tree = div.tree, id = div.node.id;
		switch (notch : ashui.layout.IntoReactive.ReactiveType<ashui.types.Notch>) {
			case Const(n):
				tree.setNotch(id, n);
			case Bound(s):
				tree.setNotch(id, s.get());
				new ashui.reactive.Watch(() -> s.get(), n -> tree.setNotch(id, n));
			case Derived(c):
				tree.setNotch(id, c.get());
				new ashui.reactive.Watch(() -> c.get(), n -> tree.setNotch(id, n));
		}
		ashui.reactive.Owner.onCleanup(() -> tree.setNotch(id, null));
	}

	/** Binds input handlers and state to the node. Creates an `Interaction` only when an input attribute is supplied. **/
	static function bindInput(node:Node, attr:DivAttributes):Void {
		if (attr.onClick == null && attr.onPointerDown == null && attr.onPointerUp == null && attr.onPointerMove == null && attr.onPointerEnter == null
			&& attr.onPointerLeave == null && attr.onWheel == null && attr.onTouchStart == null && attr.onTouchMove == null && attr.onTouchEnd == null
			&& attr.onTouchCancel == null && attr.onKeyDown == null && attr.onKeyUp == null && attr.onTextInput == null
			&& attr.onComposition == null && attr.onFocus == null && attr.onBlur == null && attr.focusable == null && attr.disabled == null)
			return;
		var i = ashui.input.Interaction.of(node);
		if (attr.onClick != null)
			i.onClick(attr.onClick);
		if (attr.onPointerDown != null)
			i.onPointerDown(attr.onPointerDown);
		if (attr.onPointerUp != null)
			i.onPointerUp(attr.onPointerUp);
		if (attr.onPointerMove != null)
			i.onPointerMove(attr.onPointerMove);
		if (attr.onPointerEnter != null)
			i.onPointerEnter(attr.onPointerEnter);
		if (attr.onPointerLeave != null)
			i.onPointerLeave(attr.onPointerLeave);
		if (attr.onWheel != null)
			i.onWheel(attr.onWheel);
		if (attr.onTouchStart != null)
			i.onTouchStart(attr.onTouchStart);
		if (attr.onTouchMove != null)
			i.onTouchMove(attr.onTouchMove);
		if (attr.onTouchEnd != null)
			i.onTouchEnd(attr.onTouchEnd);
		if (attr.onTouchCancel != null)
			i.onTouchCancel(attr.onTouchCancel);
		if (attr.onKeyDown != null)
			i.onKeyDown(attr.onKeyDown);
		if (attr.onKeyUp != null)
			i.onKeyUp(attr.onKeyUp);
		if (attr.onTextInput != null)
			i.onTextInput(attr.onTextInput);
		if (attr.onComposition != null)
			i.onComposition(attr.onComposition);
		if (attr.onFocus != null)
			i.onFocus(attr.onFocus);
		if (attr.onBlur != null)
			i.onBlur(attr.onBlur);
		if (attr.focusable != null)
			i.setFocusable(attr.focusable);
		if (attr.disabled != null)
			i.setDisabled(attr.disabled);
	}

	public function new(?attr:DivAttributes, ?children:Array<Element>, ?tree:LayoutTree) {
		super(tree);

		// Its node, made in the tree.
		var node = this.tree.createNode();
		this.node = node;
		var tag = attr != null && attr.tag != null ? attr.tag : "div";
		var identity = ashui.css.Identity.register(this.tree, node, tag);
		// A built-in element's look comes from the user-agent stylesheet.
		if (tag != "div")
			ashui.css.Css.useUserAgent();
		if (attr != null) {
			if (attr.id != null)
				identity.setId(attr.id);
			if (attr.classes != null)
				identity.setClasses(attr.classes);
		}

		// Each attribute given binds its property; the style first, so the others win.
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
			if (attr.visibility != null)
				node.set(Prop.Visibility, attr.visibility);
			if (attr.pointerEvents != null)
				node.set(Prop.PointerEvents, attr.pointerEvents);
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
			if (attr.maskImage != null)
				node.set(Prop.MaskImage, attr.maskImage);
			if (attr.notch != null)
				bindNotch(this, attr.notch);
			if (attr.animateLayout == true)
				ashui.animation.LayoutAnimation.attach(node);
			if (attr.gridTemplateColumns != null)
				node.set(Prop.GridTemplateColumns, attr.gridTemplateColumns);
			if (attr.gridTemplateRows != null)
				node.set(Prop.GridTemplateRows, attr.gridTemplateRows);
			if (attr.gridColumn != null)
				node.set(Prop.GridColumn, attr.gridColumn);
			if (attr.gridRow != null)
				node.set(Prop.GridRow, attr.gridRow);
			if (attr.display != null)
				node.set(Prop.Display, attr.display);
			if (attr.overflow != null)
				node.set(Prop.Overflow, attr.overflow);
			if (attr.virtualizeImages != null)
				ImageResidency.configure(node, attr.virtualizeImages);
			if (attr.position != null)
				node.set(Prop.Position, attr.position);
			if (attr.order != null)
				node.set(Prop.Order, attr.order);
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
			bindInput(node, attr);
		}

		// The children, placed in order.
		if (children != null) {
			for (child in children) {
				this.tree.addChild(node.id, child.node.id);
			}
		}
	}
}
