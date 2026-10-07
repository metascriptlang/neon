// react-native-paper Dialog with the Material 3 AlertDialog look: a scrim and a centred card.
// An absolutely positioned layer over its parent: place it last, at the root of the screen.

import { NeonEvent } from "../render/event";
import { Style, layerStyles } from "../render/style";
import { Accessor, accessor } from "../core/signal";
import { element } from "../macros/ui/element";
import { Show } from "../macros/ui/flow";
import { NeonNode } from "../render/node";
import { AccessibilityProps, Pressable, Text, View } from "./primitives";
import {
	MATERIAL_DISABLED,
	MATERIAL_ON_SURFACE,
	MATERIAL_PRIMARY,
	colorOr,
	flagOn,
} from "./material";

// Native hosts paint neither rgba colours nor borders, so the 50 % black scrim is opaque black
// drawn at half opacity.
const SCRIM: Style = {
	position: "absolute",
	top: 0,
	left: 0,
	right: 0,
	bottom: 0,
	zIndex: 0,
	backgroundColor: "#000000",
	opacity: 0.5,
};

export const OVERLAY_LAYER: Style = {
	position: "absolute",
	top: 0,
	left: 0,
	right: 0,
	bottom: 0,
	zIndex: 1000,
};

interface ScrimProps {
	dismissable: Accessor<boolean>;
	onDismiss: (() => void) | null;
}

// The half-black cover under a dialog or a sheet. It stays pressable while not dismissable so a
// tap never falls through to the screen below.
export function Scrim(props: ScrimProps): NeonNode {
	const { dismissable, onDismiss } = props;
	const press = (e: NeonEvent): void => {
		if (dismissable() && onDismiss !== null) { (onDismiss as () => void)(); }
	};
	return element(<Pressable style={SCRIM} onPress={press} accessibilityLabel="Dismiss" />);
}

interface DialogProps extends AccessibilityProps {
	visible: Accessor<boolean>;
	onDismiss?: (() => void) | null;
	dismissable?: Accessor<boolean> | null;
	title?: Accessor<string> | null;
	actions?: NeonNode | null;
	style?: Accessor<Style> | null;
	children?: NeonNode | null;
}

const DIALOG_LAYER: Style = {
	...OVERLAY_LAYER,
	justifyContent: "center",
	alignItems: "center",
	padding: 24,
};
const DIALOG_CARD: Style = {
	zIndex: 1,
	flexDirection: "column",
	minWidth: 280,
	maxWidth: 320,
	paddingTop: 24,
	paddingBottom: 24,
	paddingLeft: 24,
	paddingRight: 24,
	gap: 16,
	borderRadius: 28,
	backgroundColor: "#ffffff",
};
const DIALOG_TITLE: Style = { color: MATERIAL_ON_SURFACE, fontSize: 24 };
const DIALOG_CONTENT: Style = { flexDirection: "column" };
const DIALOG_ACTIONS: Style = {
	flexDirection: "row",
	justifyContent: "flex-end",
	alignItems: "center",
	gap: 8,
};

export function Dialog(props: DialogProps): NeonNode {
	const { visible, onDismiss, dismissable, title } = props;
	const userStyle = props.style;
	const canDismiss = accessor((): boolean => dismissable === null || flagOn(dismissable));
	const heading = accessor((): string => title === null ? "" : (title as Accessor<string>)());
	const labelProp = props.accessibilityLabel;
	const a11y = labelProp === null ? heading : labelProp as Accessor<string>;
	const card = accessor((): Style => userStyle === null
		? DIALOG_CARD
		: layerStyles([DIALOG_CARD, (userStyle as Accessor<Style>)()]));
	const actions = props.actions;
	const actionRow = actions === null
		? element(<View />)
		: element(<View style={DIALOG_ACTIONS}>{actions}</View>);
	return element(<Show when={visible()}>
		<View style={DIALOG_LAYER}>
			<Scrim dismissable={canDismiss()} onDismiss={onDismiss} />
			<View style={card} accessibilityRole="alert" accessibilityLabel={a11y()}>
				<Show when={title !== null}>
					<Text style={DIALOG_TITLE} accessibilityRole="header">{heading()}</Text>
				</Show>
				<View style={DIALOG_CONTENT}>{props.children}</View>
				<Show when={actions !== null}>{actionRow}</Show>
			</View>
		</View>
	</Show>);
}

interface DialogActionProps extends AccessibilityProps {
	label: Accessor<string>;
	onPress?: (() => void) | null;
	color?: Accessor<string> | null;
	disabled?: Accessor<boolean> | null;
}

// A Material 3 text button for the dialog's action row.
export function DialogAction(props: DialogActionProps): NeonNode {
	const { label, onPress, color, disabled } = props;
	const press = (e: NeonEvent): void => {
		if (flagOn(disabled) || onPress === null) { return; }
		(onPress as () => void)();
	};
	const text = accessor((): Style => ({
		color: flagOn(disabled) ? MATERIAL_DISABLED : colorOr(color, MATERIAL_PRIMARY),
		fontSize: 14,
		fontWeight: "bold",
	}));
	const box: Style = {
		minHeight: 40,
		justifyContent: "center",
		paddingLeft: 12,
		paddingRight: 12,
		borderRadius: 20,
	};
	const labelProp = props.accessibilityLabel;
	const a11y = labelProp === null ? label : labelProp as Accessor<string>;
	return element(<Pressable style={box} onPress={press}
		accessibilityRole="button" accessibilityLabel={a11y()}>
		<Text style={text}>{label()}</Text>
	</Pressable>);
}
