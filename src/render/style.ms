// Style — the portable style IR (docs/STYLE.md §3).
//
// Flat by design: one vocabulary covering layout + paint + text. Hosts project
// the subset they understand (docs/STYLE.md §5), so there is no ViewStyle /
// TextStyle split. This module must not import Yoga, void, or any host type.
//
// `null` means unset. Dimensions are `number | string`: a bare number is points,
// a string is "50%" or "auto".

export type FlexDirection = "row" | "column" | "row-reverse" | "column-reverse";
export type Justify = "flex-start" | "flex-end" | "center" | "space-between" | "space-around" | "space-evenly";
export type Align = "auto" | "flex-start" | "flex-end" | "center" | "stretch" | "baseline";
export type PositionType = "static" | "relative" | "absolute";
export type Wrap = "no-wrap" | "wrap" | "wrap-reverse";
export type Display = "flex" | "none";
export type TextAlign = "left" | "center" | "right";
export type FontWeight = "normal" | "bold";

export interface Style {
	flexDirection: FlexDirection | null;
	justifyContent: Justify | null;
	alignItems: Align | null;
	alignSelf: Align | null;
	alignContent: Align | null;
	position: PositionType | null;
	flexWrap: Wrap | null;
	display: Display | null;

	flex: number | null;
	flexGrow: number | null;
	flexShrink: number | null;
	flexBasis: number | string | null;

	width: number | string | null;
	height: number | string | null;
	minWidth: number | string | null;
	minHeight: number | string | null;
	maxWidth: number | string | null;
	maxHeight: number | string | null;
	aspectRatio: number | null;

	margin: number | string | null;
	marginTop: number | string | null;
	marginBottom: number | string | null;
	marginLeft: number | string | null;
	marginRight: number | string | null;

	padding: number | string | null;
	paddingTop: number | string | null;
	paddingBottom: number | string | null;
	paddingLeft: number | string | null;
	paddingRight: number | string | null;

	top: number | string | null;
	left: number | string | null;
	right: number | string | null;
	bottom: number | string | null;

	gap: number | string | null;
	rowGap: number | string | null;
	columnGap: number | string | null;

	backgroundColor: string | null;
	borderWidth: number | null;
	borderColor: string | null;
	borderRadius: number | null;
	opacity: number | null;

	color: string | null;
	fontSize: number | null;
	fontWeight: FontWeight | null;
	textAlign: TextAlign | null;
}

// `style={[a, b, c]}` — later layers win. The macro cannot fold this at expansion:
// the checker wraps each array element in a HiddenSubConv the macro bridge cannot
// traverse, so the layers stay opaque until runtime.
export function layerStyles(layers: Style[]): Style {
	let acc = layers[0];
	for (let i = 1; i < layers.length; i += 1) {
		acc = mergeStyle(acc, layers[i]);
	}
	return acc;
}

// One layer of `style={[base, over]}`: a field set in `over` wins, an unset one
// falls through to `base`. Written field by field because unset is `null` rather
// than absence, so a copy cannot distinguish the two without naming each field.
export function mergeStyle(base: Style, over: Style): Style {
	return {
		flexDirection: over.flexDirection !== null ? over.flexDirection : base.flexDirection,
		justifyContent: over.justifyContent !== null ? over.justifyContent : base.justifyContent,
		alignItems: over.alignItems !== null ? over.alignItems : base.alignItems,
		alignSelf: over.alignSelf !== null ? over.alignSelf : base.alignSelf,
		alignContent: over.alignContent !== null ? over.alignContent : base.alignContent,
		position: over.position !== null ? over.position : base.position,
		flexWrap: over.flexWrap !== null ? over.flexWrap : base.flexWrap,
		display: over.display !== null ? over.display : base.display,

		flex: over.flex !== null ? over.flex : base.flex,
		flexGrow: over.flexGrow !== null ? over.flexGrow : base.flexGrow,
		flexShrink: over.flexShrink !== null ? over.flexShrink : base.flexShrink,
		flexBasis: over.flexBasis !== null ? over.flexBasis : base.flexBasis,

		width: over.width !== null ? over.width : base.width,
		height: over.height !== null ? over.height : base.height,
		minWidth: over.minWidth !== null ? over.minWidth : base.minWidth,
		minHeight: over.minHeight !== null ? over.minHeight : base.minHeight,
		maxWidth: over.maxWidth !== null ? over.maxWidth : base.maxWidth,
		maxHeight: over.maxHeight !== null ? over.maxHeight : base.maxHeight,
		aspectRatio: over.aspectRatio !== null ? over.aspectRatio : base.aspectRatio,

		margin: over.margin !== null ? over.margin : base.margin,
		marginTop: over.marginTop !== null ? over.marginTop : base.marginTop,
		marginBottom: over.marginBottom !== null ? over.marginBottom : base.marginBottom,
		marginLeft: over.marginLeft !== null ? over.marginLeft : base.marginLeft,
		marginRight: over.marginRight !== null ? over.marginRight : base.marginRight,

		padding: over.padding !== null ? over.padding : base.padding,
		paddingTop: over.paddingTop !== null ? over.paddingTop : base.paddingTop,
		paddingBottom: over.paddingBottom !== null ? over.paddingBottom : base.paddingBottom,
		paddingLeft: over.paddingLeft !== null ? over.paddingLeft : base.paddingLeft,
		paddingRight: over.paddingRight !== null ? over.paddingRight : base.paddingRight,

		top: over.top !== null ? over.top : base.top,
		left: over.left !== null ? over.left : base.left,
		right: over.right !== null ? over.right : base.right,
		bottom: over.bottom !== null ? over.bottom : base.bottom,

		gap: over.gap !== null ? over.gap : base.gap,
		rowGap: over.rowGap !== null ? over.rowGap : base.rowGap,
		columnGap: over.columnGap !== null ? over.columnGap : base.columnGap,

		backgroundColor: over.backgroundColor !== null ? over.backgroundColor : base.backgroundColor,
		borderWidth: over.borderWidth !== null ? over.borderWidth : base.borderWidth,
		borderColor: over.borderColor !== null ? over.borderColor : base.borderColor,
		borderRadius: over.borderRadius !== null ? over.borderRadius : base.borderRadius,
		opacity: over.opacity !== null ? over.opacity : base.opacity,

		color: over.color !== null ? over.color : base.color,
		fontSize: over.fontSize !== null ? over.fontSize : base.fontSize,
		fontWeight: over.fontWeight !== null ? over.fontWeight : base.fontWeight,
		textAlign: over.textAlign !== null ? over.textAlign : base.textAlign,
	};
}
