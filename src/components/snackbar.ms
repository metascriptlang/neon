// react-native-paper Snackbar with Flutter SnackBar's look and its 4 s default duration.
// An absolutely positioned layer pinned to the bottom: place it last, at the root of the screen.

import { NeonEvent } from "../render/event";
import { Style, layerStyles } from "../render/style";
import { createEffect } from "../core/effect";
import { onCleanup } from "../core/cleanup";
import { Accessor, accessor } from "../core/signal";
import { element } from "../macros/ui/element";
import { Show } from "../macros/ui/flow";
import { NeonNode } from "../render/node";
import { Host, HostNode } from "../render/hostTypes";
import { AccessibilityProps, Pressable, Text, View } from "./primitives";
import { colorOr } from "./material";

export interface SnackbarAction {
	label: string;
	onPress: () => void;
}

interface SnackbarProps extends AccessibilityProps {
	visible: Accessor<boolean>;
	onDismiss?: (() => void) | null;
	duration?: Accessor<int32> | null;
	message?: Accessor<string> | null;
	action?: Accessor<SnackbarAction> | null;
	actionLabel?: Accessor<string> | null;
	onActionPress?: (() => void) | null;
	actionColor?: Accessor<string> | null;
	style?: Accessor<Style> | null;
	children?: NeonNode | null;
}

// Flutter SnackBar: 4 s on screen, `#323232` surface, inverse-primary action.
export const SNACKBAR_DURATION_MS = 4000;
const SNACKBAR_SURFACE = "#323232";
const SNACKBAR_ACTION = "#90caf9";

const SNACKBAR_LAYER: Style = {
	position: "absolute",
	left: 8,
	right: 8,
	bottom: 8,
	zIndex: 1000,
	flexDirection: "row",
	alignItems: "center",
	minHeight: 48,
	paddingLeft: 16,
	paddingRight: 8,
	borderRadius: 4,
	backgroundColor: SNACKBAR_SURFACE,
};
const SNACKBAR_MESSAGE: Style = { flex: 1, paddingTop: 14, paddingBottom: 14 };
const SNACKBAR_TEXT: Style = { color: "#ffffff", fontSize: 14 };
const SNACKBAR_ACTION_BOX: Style = {
	paddingLeft: 8,
	paddingRight: 8,
	paddingTop: 10,
	paddingBottom: 10,
};

// Starts `duration` ms each time `visible` turns true and clears it when the snackbar hides or
// unmounts, so a dismissal never reaches a snackbar that is already gone.
export function autoDismiss(
	visible: Accessor<boolean>,
	duration: () => int32,
	onDismiss: (() => void) | null,
): void {
	createEffect((): void => {
		if (!visible() || onDismiss === null) { return; }
		const id = setTimeout((): void => { (onDismiss as () => void)(); }, duration()) as int32;
		onCleanup((): void => { clearTimeout(id); });
	});
}

export function Snackbar(props: SnackbarProps): NeonNode {
	const { visible, onDismiss, duration, action, actionLabel, onActionPress, actionColor } = props;
	const message = props.message;
	const userStyle = props.style;
	const hasAction = action !== null || actionLabel !== null;
	const label = accessor((): string => {
		if (action !== null) { return (action as Accessor<SnackbarAction>)().label; }
		return actionLabel === null ? "" : (actionLabel as Accessor<string>)();
	});
	const pressAction = (e: NeonEvent): void => {
		if (action !== null) { (action as Accessor<SnackbarAction>)().onPress(); }
		if (onActionPress !== null) { (onActionPress as () => void)(); }
		if (onDismiss !== null) { (onDismiss as () => void)(); }
	};
	const layer = accessor((): Style => userStyle === null
		? SNACKBAR_LAYER
		: layerStyles([SNACKBAR_LAYER, (userStyle as Accessor<Style>)()]));
	const actionText = accessor((): Style => ({
		color: colorOr(actionColor, SNACKBAR_ACTION),
		fontSize: 14,
		fontWeight: "bold",
	}));
	const text = accessor((): string => message === null ? "" : (message as Accessor<string>)());
	const labelProp = props.accessibilityLabel;
	const a11y = labelProp === null ? text : labelProp as Accessor<string>;
	const body = message === null
		? element(<View style={SNACKBAR_MESSAGE}>{props.children}</View>)
		: element(<View style={SNACKBAR_MESSAGE}>
			<Text style={SNACKBAR_TEXT}>{text()}</Text>
		</View>);
	const bar = element(<Show when={visible()}>
		<View style={layer} accessibilityRole="alert" accessibilityLabel={a11y()}>
			{body}
			<Show when={hasAction}>
				<Pressable style={SNACKBAR_ACTION_BOX} onPress={pressAction}
					accessibilityRole="button" accessibilityLabel={label()}>
					<Text style={actionText}>{label().toUpperCase()}</Text>
				</Pressable>
			</Show>
		</View>
	</Show>);
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const ms = (): int32 => duration === null
			? SNACKBAR_DURATION_MS
			: (duration as Accessor<int32>)();
		autoDismiss(visible, ms, onDismiss);
		bar(host, parent, before);
	};
}
