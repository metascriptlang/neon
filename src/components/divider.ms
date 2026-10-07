// Flutter's Divider and VerticalDivider, react-native-paper's Divider: a filled line, since
// native hosts paint no borders. `inset` is paper's 16pt leading inset; `indent` and
// `endIndent` are Flutter's and add to it.

import { Style } from "../render/style";
import { Accessor } from "../core/signal";
import { NeonNode, VAttr, hostElement } from "../render/node";
import { layered } from "./drawn";
import { AccessibilityProps, accessibilityAttrs } from "./primitives";
import { colorOr, flagOn } from "./material";

interface DividerProps extends AccessibilityProps {
	inset?: Accessor<boolean> | null;
	indent?: Accessor<float64> | null;
	endIndent?: Accessor<float64> | null;
	thickness?: Accessor<float64> | null;
	color?: Accessor<string> | null;
	vertical?: Accessor<boolean> | null;
	style?: Accessor<Style> | null;
}

const DIVIDER_COLOR = "#e0e0e0";
const INSET = 16.0;

function amount(value: Accessor<float64> | null, fallback: float64): float64 {
	return value === null ? fallback : (value as Accessor<float64>)();
}

export function Divider(props: DividerProps): NeonNode {
	const { inset, indent, endIndent, thickness, color, vertical } = props;
	const line = (): Style => {
		const lead = (flagOn(inset) ? INSET : 0.0) + amount(indent, 0.0);
		const trail = amount(endIndent, 0.0);
		const t = amount(thickness, 1.0);
		const paint = colorOr(color, DIVIDER_COLOR);
		if (flagOn(vertical)) {
			return {
				width: t, alignSelf: "stretch", marginTop: lead, marginBottom: trail,
				backgroundColor: paint,
			};
		}
		return {
			height: t, alignSelf: "stretch", marginLeft: lead, marginRight: trail,
			backgroundColor: paint,
		};
	};
	const attrs: VAttr[] = [];
	accessibilityAttrs(props, attrs);
	return hostElement("view", attrs, [], null, layered(line, props.style), null);
}
