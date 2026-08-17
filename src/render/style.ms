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

// Every style field's value fits this one union: string-literal unions are
// strings at runtime, dimensions are number | string, null means unset. It is
// the wire type of the per-property channel (setStyleProp / VDynStyle).
export type StyleValue = number | string | null;

export function emptyStyle(): Style {
	return {};
}

// The per-property write behind reactive style fields (docs/STYLE.md §6). One
// switch instead of 40 setters on every host; the enum-ish fields narrow from
// the wire union with a cast because the checker cannot see which names carry
// which member.
export function setStyleField(s: Style, name: string, v: StyleValue): void {
	match (name) {
		"flexDirection" => { s.flexDirection = v as unknown as FlexDirection | null; },
		"justifyContent" => { s.justifyContent = v as unknown as Justify | null; },
		"alignItems" => { s.alignItems = v as unknown as Align | null; },
		"alignSelf" => { s.alignSelf = v as unknown as Align | null; },
		"alignContent" => { s.alignContent = v as unknown as Align | null; },
		"position" => { s.position = v as unknown as PositionType | null; },
		"flexWrap" => { s.flexWrap = v as unknown as Wrap | null; },
		"display" => { s.display = v as unknown as Display | null; },
		"flex" => { s.flex = v as unknown as number | null; },
		"flexGrow" => { s.flexGrow = v as unknown as number | null; },
		"flexShrink" => { s.flexShrink = v as unknown as number | null; },
		"flexBasis" => { s.flexBasis = v; },
		"width" => { s.width = v; },
		"height" => { s.height = v; },
		"minWidth" => { s.minWidth = v; },
		"minHeight" => { s.minHeight = v; },
		"maxWidth" => { s.maxWidth = v; },
		"maxHeight" => { s.maxHeight = v; },
		"aspectRatio" => { s.aspectRatio = v as unknown as number | null; },
		"margin" => { s.margin = v; },
		"marginTop" => { s.marginTop = v; },
		"marginBottom" => { s.marginBottom = v; },
		"marginLeft" => { s.marginLeft = v; },
		"marginRight" => { s.marginRight = v; },
		"padding" => { s.padding = v; },
		"paddingTop" => { s.paddingTop = v; },
		"paddingBottom" => { s.paddingBottom = v; },
		"paddingLeft" => { s.paddingLeft = v; },
		"paddingRight" => { s.paddingRight = v; },
		"top" => { s.top = v; },
		"left" => { s.left = v; },
		"right" => { s.right = v; },
		"bottom" => { s.bottom = v; },
		"gap" => { s.gap = v; },
		"rowGap" => { s.rowGap = v; },
		"columnGap" => { s.columnGap = v; },
		"backgroundColor" => { s.backgroundColor = v as unknown as string | null; },
		"borderWidth" => { s.borderWidth = v as unknown as number | null; },
		"borderColor" => { s.borderColor = v as unknown as string | null; },
		"borderRadius" => { s.borderRadius = v as unknown as number | null; },
		"opacity" => { s.opacity = v as unknown as number | null; },
		"color" => { s.color = v as unknown as string | null; },
		"fontSize" => { s.fontSize = v as unknown as number | null; },
		"fontWeight" => { s.fontWeight = v as unknown as FontWeight | null; },
		"textAlign" => { s.textAlign = v as unknown as TextAlign | null; },
		_ => {},
	};
}

// `style={[a, b, c]}` — later layers win at runtime when a layer is a sheet
// reference; all-literal arrays merge at expansion instead (element macro, S3).
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
