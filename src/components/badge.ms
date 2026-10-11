// react-native-paper's Badge: a pill holding a short value (`value`, or text children), or a
// small dot when it holds nothing. `visible={false}` hides it without unmounting it.

import { Style } from "../render/style";
import { Accessor, accessor } from "../core/signal";
import { element } from "../macros/ui/element";
import { NeonNode, VAttr, dynAttr, hostElement } from "../render/node";
import { defaultRole, layered } from "./drawn";
import { AccessibilityProps, Text, accessibilityAttrs } from "./primitives";
import { colorOr } from "./material";

interface BadgeProps extends AccessibilityProps {
	value?: Accessor<string> | null;
	children?: NeonNode | null;
	visible?: Accessor<boolean> | null;
	size?: Accessor<int32> | null;
	color?: Accessor<string> | null;
	backgroundColor?: Accessor<string> | null;
	style?: Accessor<Style> | null;
}

const BADGE_SIZE = 20;
const DOT_SIZE = 6;
const BADGE_COLOR = "#b3261e";
const BADGE_TEXT = "#ffffff";

export function Badge(props: BadgeProps): NeonNode {
	const { value, children, visible, size, color, backgroundColor } = props;
	const hasContent = value !== null || children !== null;
	const side = (): int32 => {
		if (size !== null) { return (size as Accessor<int32>)(); }
		return hasContent ? BADGE_SIZE : DOT_SIZE;
	};
	const shown = (): boolean => visible === null || (visible as Accessor<boolean>)();
	const pill = (): Style => {
		const s: Style = {
			height: side(), minWidth: side(), borderRadius: side() / 2,
			paddingLeft: hasContent ? 4 : 0, paddingRight: hasContent ? 4 : 0,
			alignSelf: "flex-start", alignItems: "center", justifyContent: "center",
			backgroundColor: colorOr(backgroundColor, BADGE_COLOR),
		};
		if (!shown()) { return { ...s, display: "none" }; }
		return s;
	};
	const attrs: VAttr[] = [];
	if (hasContent) { defaultRole(attrs, props.accessibilityRole === null, "text"); }
	if (props.accessibilityLabel === null && value !== null) {
		const read = value as Accessor<string>;
		attrs.push(dynAttr("accessibilityLabel", (): string | null => read()));
	}
	accessibilityAttrs(props, attrs);
	const ink = accessor((): Style => ({
		color: colorOr(color, BADGE_TEXT), fontSize: side() * 3 / 5, fontWeight: "bold",
	}));
	let kids: NeonNode | null = null;
	if (value !== null) {
		const read = value as Accessor<string>;
		kids = element(<Text style={ink}>{read()}</Text>);
	} else if (children !== null) {
		kids = element(<Text style={ink}>{children}</Text>);
	}
	return hostElement("view", attrs, [], kids, layered(pill, props.style), null);
}
