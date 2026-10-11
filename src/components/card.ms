// A Material card: Flutter's Card and react-native-paper's Card with Card.Title, Card.Content
// and Card.Actions. Native hosts paint no shadows, so elevation is a darker edge under the
// surface, one point per level (0 to 5): the edge view carries the caller's layout style and
// the surface inside it carries the caller's background and corner radius.

import { NeonEvent } from "../render/event";
import { Style, layerStyles } from "../render/style";
import { Accessor, accessor } from "../core/signal";
import { element } from "../macros/ui/element";
import { NeonNode, VAttr, VEvent, evt, hostElement } from "../render/node";
import { defaultRole } from "./drawn";
import { AccessibilityProps, Text, View, accessibilityAttrs } from "./primitives";
import { MATERIAL_ON_SURFACE, MATERIAL_SURFACE } from "./material";

interface CardProps extends AccessibilityProps {
	children?: NeonNode | null;
	onPress?: ((e: NeonEvent) => void) | null;
	elevation?: Accessor<int32> | null;
	style?: Accessor<Style> | null;
}

const EDGE = "#d0d0d0";
const RADIUS = 12;
const MAX_ELEVATION = 5;

export function cardEdge(elevation: int32): int32 {
	return Math.min(Math.max(elevation, 0), MAX_ELEVATION);
}

export function Card(props: CardProps): NeonNode {
	const { elevation, onPress } = props;
	const user = props.style;
	const level = (): int32 => cardEdge(elevation === null ? 1 : (elevation as Accessor<int32>)());
	const layout = (): Style => {
		const base: Style = { flexDirection: "column", borderRadius: RADIUS };
		return user === null ? base : layerStyles([base, (user as () => Style)()]);
	};
	const edge = accessor((): Style => ({
		...layout(),
		backgroundColor: level() === 0 ? null : EDGE,
		paddingTop: 0, paddingLeft: 0, paddingRight: 0, paddingBottom: level(),
	}));
	const surface = accessor((): Style => {
		const outer = layout();
		const color = outer.backgroundColor;
		return {
			flexDirection: "column", overflow: "hidden",
			borderRadius: outer.borderRadius,
			backgroundColor: color === null ? MATERIAL_SURFACE : color,
		};
	});
	const kids = element(<View style={surface}>{props.children}</View>);
	const attrs: VAttr[] = [];
	const evts: VEvent[] = [];
	if (onPress !== null) {
		defaultRole(attrs, props.accessibilityRole === null, "button");
		evts.push(evt("onPress", onPress as (e: NeonEvent) => void));
	}
	accessibilityAttrs(props, attrs);
	const tag = onPress === null ? "view" : "pressable";
	return hostElement(tag, attrs, evts, kids, edge as () => Style, null);
}

const TITLE_BOX: Style = {
	flexDirection: "column", paddingLeft: 16, paddingRight: 16, paddingTop: 16, paddingBottom: 8,
};
const TITLE_TEXT: Style = { fontSize: 18, fontWeight: "bold", color: MATERIAL_ON_SURFACE };
const SUBTITLE_TEXT: Style = { fontSize: 14, color: "#49454f" };

export function CardTitle(props: {
	title: Accessor<string>;
	subtitle?: Accessor<string> | null;
}): NeonNode {
	const title = props.title;
	const subtitle = props.subtitle;
	if (subtitle === null) {
		return element(<View style={TITLE_BOX}>
			<Text style={TITLE_TEXT} accessibilityRole="header">{title()}</Text>
		</View>);
	}
	const read = subtitle as Accessor<string>;
	return element(<View style={TITLE_BOX}>
		<Text style={TITLE_TEXT} accessibilityRole="header">{title()}</Text>
		<Text style={SUBTITLE_TEXT}>{read()}</Text>
	</View>);
}

const CONTENT_BOX: Style = {
	flexDirection: "column", paddingLeft: 16, paddingRight: 16, paddingBottom: 16,
};

export function CardContent(props: { children?: NeonNode | null }): NeonNode {
	return element(<View style={CONTENT_BOX}>{props.children}</View>);
}

const ACTIONS_BOX: Style = {
	flexDirection: "row", justifyContent: "flex-end", alignItems: "center", gap: 8, padding: 8,
};

export function CardActions(props: { children?: NeonNode | null }): NeonNode {
	return element(<View style={ACTIONS_BOX}>{props.children}</View>);
}
