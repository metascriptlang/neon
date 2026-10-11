// Flutter widgets/wrap.dart (rendering/wrap.dart RenderWrap) over flexbox wrapping:
// `spacing` is the gap between children in a run, `runSpacing` the gap between runs,
// `alignment` places the children of a run, `runAlignment` the runs, and
// `crossAxisAlignment` a child within its run.

import { Accessor, accessor } from "../core/signal";
import { NeonNode } from "../render/node";
import { Align, Justify, Style, mergeStyle } from "../render/style";
import { View } from "./primitives";

export type WrapDirection = "horizontal" | "vertical";
export type WrapAlignment = "start" | "end" | "center" | "spaceBetween" | "spaceAround" | "spaceEvenly";
export type WrapCrossAlignment = "start" | "end" | "center";

// `if` returns, not `match`: literal arms widen to string (compiler card
// 2026-10-08-match-arms-of-string-literals-widen-to-string.md, WORKAROUND.md W5).
export function wrapJustify(alignment: WrapAlignment): Justify {
	if (alignment === "start") { return "flex-start"; }
	if (alignment === "end") { return "flex-end"; }
	if (alignment === "center") { return "center"; }
	if (alignment === "spaceBetween") { return "space-between"; }
	if (alignment === "spaceAround") { return "space-around"; }
	return "space-evenly";
}

// Style's alignContent carries no space-* value yet, so a spaced run alignment is refused
// where it is asked for (WORKAROUND.md W4).
export function wrapRunAlign(alignment: WrapAlignment): Align {
	if (alignment === "start") { return "flex-start"; }
	if (alignment === "end") { return "flex-end"; }
	if (alignment === "center") { return "center"; }
	throw `Wrap: runAlignment "${alignment}" needs a space-* alignContent, which Neon's Style does not carry`;
}

export function wrapCrossAlign(alignment: WrapCrossAlignment): Align {
	if (alignment === "start") { return "flex-start"; }
	if (alignment === "end") { return "flex-end"; }
	return "center";
}

export function wrapStyle(direction: WrapDirection, alignment: WrapAlignment, runAlignment: WrapAlignment, cross: WrapCrossAlignment, spacing: number, runSpacing: number): Style {
	const horizontal = direction === "horizontal";
	return {
		flexDirection: horizontal ? "row" : "column",
		flexWrap: "wrap",
		justifyContent: wrapJustify(alignment),
		alignContent: wrapRunAlign(runAlignment),
		alignItems: wrapCrossAlign(cross),
		columnGap: horizontal ? spacing : runSpacing,
		rowGap: horizontal ? runSpacing : spacing,
	};
}

export function Wrap(props: {
	children?: NeonNode | null;
	direction?: Accessor<WrapDirection> | null;
	alignment?: Accessor<WrapAlignment> | null;
	runAlignment?: Accessor<WrapAlignment> | null;
	crossAxisAlignment?: Accessor<WrapCrossAlignment> | null;
	spacing?: Accessor<number> | null;
	runSpacing?: Accessor<number> | null;
	style?: Accessor<Style> | null;
}): NeonNode {
	const directionProp = props.direction;
	const alignmentProp = props.alignment;
	const runProp = props.runAlignment;
	const crossProp = props.crossAxisAlignment;
	const spacingProp = props.spacing;
	const runSpacingProp = props.runSpacing;
	const userStyle = props.style;
	const style = accessor((): Style => {
		const base = wrapStyle(
			directionProp === null ? "horizontal" : (directionProp as Accessor<WrapDirection>)(),
			alignmentProp === null ? "start" : (alignmentProp as Accessor<WrapAlignment>)(),
			runProp === null ? "start" : (runProp as Accessor<WrapAlignment>)(),
			crossProp === null ? "start" : (crossProp as Accessor<WrapCrossAlignment>)(),
			spacingProp === null ? 0 : (spacingProp as Accessor<number>)(),
			runSpacingProp === null ? 0 : (runSpacingProp as Accessor<number>)(),
		);
		return userStyle === null ? base : mergeStyle(base, (userStyle as Accessor<Style>)());
	});
	return View({ style, children: props.children });
}
