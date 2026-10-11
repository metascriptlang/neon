import { NeonEvent } from "../render/event";
import { Style, layerStyles } from "../render/style";
import { Accessor, accessor } from "../core/signal";
import { NeonNode, VAttr, VEvent, hostElement, evt, dynAttr } from "../render/node";
import { AccessibilityProps, accessibilityAttrs, flagAttr, stringAttr } from "./primitives";

export type IndicatorSize = "small" | "large";

interface ActivityIndicatorProps extends AccessibilityProps {
	animating?: Accessor<boolean> | null;
	color?: Accessor<string> | null;
	size?: Accessor<IndicatorSize> | null;
	hidesWhenStopped?: Accessor<boolean> | null;
	style?: Accessor<Style> | null;
	onLayout?: ((e: NeonEvent) => void) | null;
}

const SMALL: Style = { width: 20, height: 20, alignItems: "center", justifyContent: "center" };
const LARGE: Style = { width: 36, height: 36, alignItems: "center", justifyContent: "center" };

export function ActivityIndicator(props: ActivityIndicatorProps): NeonNode {
	const attrs: VAttr[] = [];
	const animating = props.animating;
	attrs.push(dynAttr("animating", (): string | null => animating === null || (animating as Accessor<boolean>)() ? "true" : "false"));
	flagAttr(attrs, "hidesWhenStopped", props.hidesWhenStopped);
	stringAttr(attrs, "color", props.color);
	if (props.accessibilityRole === null) { attrs.push(dynAttr("accessibilityRole", (): string | null => "progressbar")); }
	accessibilityAttrs(props, attrs);
	const evts: VEvent[] = [];
	if (props.onLayout !== null) { evts.push(evt("onLayout", props.onLayout as (e: NeonEvent) => void)); }
	const size = props.size;
	const user = props.style;
	const style = accessor((): Style => {
		let large = false;
		if (size !== null) {
			const read = size as Accessor<IndicatorSize>;
			const s: IndicatorSize = read();
			large = s === "large";
		}
		const base = large ? LARGE : SMALL;
		return user === null ? base : layerStyles([base, (user as () => Style)()]);
	});
	return hostElement("activityindicator", attrs, evts, null, style as () => Style, null);
}
