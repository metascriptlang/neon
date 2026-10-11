import { NeonEvent } from "../render/event";
import { Style, layerStyles } from "../render/style";
import { Accessor, accessor } from "../core/signal";
import { NeonNode } from "../render/node";
import { EdgeInsets, useSafeAreaInsets } from "../render/environment";
import { AccessibilityProps, View } from "./primitives";

interface SafeAreaViewProps extends AccessibilityProps {
	style?: Accessor<Style> | null;
	onLayout?: ((e: NeonEvent) => void) | null;
	children?: NeonNode | null;
}

function points(side: number | string | null, all: number | string | null): number {
	if (side !== null && typeof side !== "string") { return side as number; }
	if (all !== null && typeof all !== "string") { return all as number; }
	return 0;
}

// RN SafeAreaView pads its content out of the unsafe areas; the insets come
// from the host (`useSafeAreaInsets`) and add to the style's own padding.
export function SafeAreaView(props: SafeAreaViewProps): NeonNode {
	const insets = useSafeAreaInsets();
	const user = props.style;
	const style = accessor((): Style => {
		const own: Style = user === null ? {} : (user as () => Style)();
		const edge: EdgeInsets = insets();
		return layerStyles([own, {
			paddingTop: points(own.paddingTop, own.padding) + edge.top,
			paddingRight: points(own.paddingRight, own.padding) + edge.right,
			paddingBottom: points(own.paddingBottom, own.padding) + edge.bottom,
			paddingLeft: points(own.paddingLeft, own.padding) + edge.left,
		}]);
	});
	return View({
		style,
		accessible: props.accessible,
		accessibilityLabel: props.accessibilityLabel,
		accessibilityHint: props.accessibilityHint,
		accessibilityRole: props.accessibilityRole,
		onLayout: props.onLayout,
		children: props.children,
	});
}
