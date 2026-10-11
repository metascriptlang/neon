// RN's legacy touchables (Libraries/Components/Touchable/*.js) over Pressable:
// the same press lifecycle, plus the feedback each one paints while pressed.

import { NeonEvent } from "../render/event";
import { Style, layerStyles } from "../render/style";
import { Accessor, accessor, createSignal } from "../core/signal";
import { NeonNode } from "../render/node";
import { AccessibilityProps, Pressable, View } from "./primitives";

interface TouchableProps extends AccessibilityProps {
	onPress?: ((e: NeonEvent) => void) | null;
	onPressIn?: ((e: NeonEvent) => void) | null;
	onPressOut?: ((e: NeonEvent) => void) | null;
	onLongPress?: ((e: NeonEvent) => void) | null;
	delayLongPress?: Accessor<number> | null;
	disabled?: Accessor<boolean> | null;
	onLayout?: ((e: NeonEvent) => void) | null;
	children?: NeonNode | null;
}

interface TouchableOpacityProps extends TouchableProps {
	activeOpacity?: Accessor<number> | null;
	style?: Accessor<Style> | null;
}

interface TouchableHighlightProps extends TouchableProps {
	activeOpacity?: Accessor<number> | null;
	underlayColor?: Accessor<string> | null;
	style?: Accessor<Style> | null;
}

type PressHandler = ((e: NeonEvent) => void) | null;

class PressFeedback {
	pressed: Accessor<boolean>;
	onPress: PressHandler;
	onPressIn: PressHandler;
	onPressOut: PressHandler;
	onLongPress: PressHandler;

	constructor(props: TouchableProps) {
		const [pressed, setPressed] = createSignal(false);
		this.pressed = pressed;
		const disabled = props.disabled;
		const off = (): boolean => disabled !== null && (disabled as Accessor<boolean>)();
		const press = props.onPress;
		const pressIn = props.onPressIn;
		const pressOut = props.onPressOut;
		const longPress = props.onLongPress;
		this.onPress = (e: NeonEvent): void => {
			if (!off() && press !== null) { (press as (x: NeonEvent) => void)(e); }
		};
		this.onPressIn = (e: NeonEvent): void => {
			if (off()) { return; }
			setPressed(true);
			if (pressIn !== null) { (pressIn as (x: NeonEvent) => void)(e); }
		};
		this.onPressOut = (e: NeonEvent): void => {
			if (!pressed()) { return; }
			setPressed(false);
			if (pressOut !== null) { (pressOut as (x: NeonEvent) => void)(e); }
		};
		this.onLongPress = longPress === null ? null : (e: NeonEvent): void => {
			if (!off()) { (longPress as (x: NeonEvent) => void)(e); }
		};
	}
}

function touchable(props: TouchableProps, feedback: PressFeedback, style: Accessor<Style> | null, children: NeonNode | null): NeonNode {
	return Pressable({
		style,
		accessible: props.accessible,
		accessibilityLabel: props.accessibilityLabel,
		accessibilityHint: props.accessibilityHint,
		accessibilityRole: props.accessibilityRole,
		onPress: feedback.onPress,
		onPressIn: feedback.onPressIn,
		onPressOut: feedback.onPressOut,
		onLongPress: feedback.onLongPress,
		delayLongPress: props.delayLongPress,
		onLayout: props.onLayout,
		children,
	});
}

// TouchableOpacity.js: the whole touchable fades to activeOpacity (0.2) while
// pressed and back to its style's opacity on release.
export function TouchableOpacity(props: TouchableOpacityProps): NeonNode {
	const feedback = new PressFeedback(props);
	const user = props.style;
	const active = props.activeOpacity;
	const style = accessor((): Style => {
		const own: Style = user === null ? {} : (user as () => Style)();
		const rest = own.opacity ?? 1;
		const pressedOpacity = active === null ? 0.2 : (active as Accessor<number>)();
		return layerStyles([own, { opacity: feedback.pressed() ? pressedOpacity : rest }]);
	});
	return touchable(props, feedback, style, props.children);
}

// TouchableHighlight.js: while pressed the underlay (black) shows through the
// child, which drops to activeOpacity (0.85). RN restyles its single child;
// here the child sits in a wrapper View that takes the opacity.
export function TouchableHighlight(props: TouchableHighlightProps): NeonNode {
	const feedback = new PressFeedback(props);
	const user = props.style;
	const underlay = props.underlayColor;
	const active = props.activeOpacity;
	const style = accessor((): Style => {
		const own: Style = user === null ? {} : (user as () => Style)();
		const rest = own.backgroundColor ?? "transparent";
		const shown = underlay === null ? "#000000" : (underlay as Accessor<string>)();
		return layerStyles([own, { backgroundColor: feedback.pressed() ? shown : rest }]);
	});
	const childStyle = accessor((): Style => {
		const pressedOpacity = active === null ? 0.85 : (active as Accessor<number>)();
		return { opacity: feedback.pressed() ? pressedOpacity : 1 };
	});
	const child = View({ style: childStyle, children: props.children });
	return touchable(props, feedback, style, child);
}

// TouchableWithoutFeedback.js gives its single child the press handlers; Neon
// cannot restyle a child NeonNode, so the child sits in an unstyled Pressable.
export function TouchableWithoutFeedback(props: TouchableProps): NeonNode {
	const feedback = new PressFeedback(props);
	return touchable(props, feedback, null, props.children);
}
