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
