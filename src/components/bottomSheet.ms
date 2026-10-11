// Flutter showModalBottomSheet as a component: a scrim and a sheet docked at the bottom with the
// Material 3 drag handle. An absolutely positioned layer: place it last, at the root of the screen.
// Native hosts paint one uniform radius, so the sheet's bottom corners round as well.

import { Style, layerStyles } from "../render/style";
import { Accessor, accessor } from "../core/signal";
import { element } from "../macros/ui/element";
import { Show } from "../macros/ui/flow";
import { NeonNode } from "../render/node";
import { Host, HostNode } from "../render/hostTypes";
import { AccessibilityProps, View } from "./primitives";
import { flagOn } from "./material";
import { BackDismiss, OVERLAY_LAYER, Scrim } from "./dialog";

interface BottomSheetProps extends AccessibilityProps {
	visible: Accessor<boolean>;
	onDismiss?: (() => void) | null;
	dismissable?: Accessor<boolean> | null;
	height?: Accessor<int32> | null;
	style?: Accessor<Style> | null;
	children?: NeonNode | null;
}

const SHEET_LAYER: Style = { ...OVERLAY_LAYER, justifyContent: "flex-end" };
const SHEET: Style = {
	zIndex: 1,
	flexDirection: "column",
	paddingBottom: 24,
	borderRadius: 28,
	backgroundColor: "#ffffff",
};
// Material 3 drag handle: 32 x 4, on-surface-variant at 40 %, 22 points above and below.
const SHEET_HANDLE: Style = {
	alignSelf: "center",
	width: 32,
	height: 4,
	marginTop: 22,
	marginBottom: 22,
	borderRadius: 2,
	backgroundColor: "#49454f",
	opacity: 0.4,
};
const SHEET_CONTENT: Style = { flexDirection: "column", flexShrink: 1 };

export function BottomSheet(props: BottomSheetProps): NeonNode {
	const { visible, onDismiss, dismissable, height } = props;
	const userStyle = props.style;
	const canDismiss = accessor((): boolean => dismissable === null || flagOn(dismissable));
	const sheet = accessor((): Style => {
		const sized: Style = height === null
			? SHEET
			: { ...SHEET, height: (height as Accessor<int32>)() as float64 };
		return userStyle === null ? sized : layerStyles([sized, (userStyle as Accessor<Style>)()]);
	});
	const handle = element(<View style={SHEET_HANDLE} />);
	const content = element(<View style={SHEET_CONTENT}>{props.children}</View>);
	const body: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		handle(host, parent, before);
		content(host, parent, before);
	};
	// Called as a function so the author's nullable accessibility accessors pass through as is.
	const panel = View({
		style: sheet,
		accessible: props.accessible,
		accessibilityLabel: props.accessibilityLabel,
		accessibilityHint: props.accessibilityHint,
		accessibilityRole: props.accessibilityRole,
		children: body,
	});
	return element(<Show when={visible()}>
		<View style={SHEET_LAYER}>
			<BackDismiss dismissable={canDismiss()} onDismiss={onDismiss} />
			<Scrim dismissable={canDismiss()} onDismiss={onDismiss} />
			{panel}
		</View>
	</Show>);
}
