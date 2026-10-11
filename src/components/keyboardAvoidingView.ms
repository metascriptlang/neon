import { NeonEvent } from "../render/event";
import { Style, layerStyles } from "../render/style";
import { Accessor, accessor, createSignal } from "../core/signal";
import { NeonNode } from "../render/node";
import { useKeyboard } from "../render/environment";
import { AccessibilityProps, View } from "./primitives";

export type KeyboardAvoidingBehavior = "height" | "position" | "padding";

interface KeyboardAvoidingViewProps extends AccessibilityProps {
	behavior?: Accessor<KeyboardAvoidingBehavior> | null;
	keyboardVerticalOffset?: Accessor<number> | null;
	enabled?: Accessor<boolean> | null;
	style?: Accessor<Style> | null;
	contentContainerStyle?: Accessor<Style> | null;
	onLayout?: ((e: NeonEvent) => void) | null;
	children?: NeonNode | null;
}

// RN Libraries/Components/Keyboard/KeyboardAvoidingView.js. RN measures how far
// the keyboard's frame overlaps this view; the hosts publish only the keyboard
// height, so the overlap is that height less keyboardVerticalOffset, as if the
// view reached the bottom of the window.
export function KeyboardAvoidingView(props: KeyboardAvoidingViewProps): NeonNode {
	const keyboard = useKeyboard();
	const { behavior, keyboardVerticalOffset, enabled } = props;
	const bottom = accessor((): number => {
		if (enabled !== null && !(enabled as Accessor<boolean>)()) { return 0; }
		const k = keyboard();
		if (!k.visible) { return 0; }
		const offset = keyboardVerticalOffset === null ? 0 : (keyboardVerticalOffset as Accessor<number>)();
		return Math.max(0, k.height - offset);
	});
	const mode = (): string => {
		if (behavior === null) { return ""; }
		const b: KeyboardAvoidingBehavior = (behavior as Accessor<KeyboardAvoidingBehavior>)();
		return b;
	};
	const [frameHeight, setFrameHeight] = createSignal<number>(-1);
	const userLayout = props.onLayout;
	const layout = (e: NeonEvent): void => {
		if (frameHeight() < 0 || bottom() === 0) { setFrameHeight(e.height); }
		if (userLayout !== null) { (userLayout as (x: NeonEvent) => void)(e); }
	};
	const user = props.style;
	const style = accessor((): Style => {
		const own: Style = user === null ? {} : (user as () => Style)();
		const m = mode();
		if (m === "padding") { return layerStyles([own, { paddingBottom: bottom() }]); }
		if (m === "height" && frameHeight() >= 0 && bottom() > 0) {
			return layerStyles([own, { height: frameHeight() - bottom(), flex: 0 }]);
		}
		return own;
	});
	const contentUser = props.contentContainerStyle;
	const shifted = accessor((): Style => {
		const own: Style = contentUser === null ? {} : (contentUser as () => Style)();
		return mode() === "position" ? layerStyles([{ position: "relative" }, own, { bottom: bottom() }]) : own;
	});
	const kids = mode() === "position" ? View({ style: shifted, children: props.children }) : props.children;
	return View({
		style,
		accessible: props.accessible,
		accessibilityLabel: props.accessibilityLabel,
		accessibilityHint: props.accessibilityHint,
		accessibilityRole: props.accessibilityRole,
		onLayout: layout,
		children: kids,
	});
}
