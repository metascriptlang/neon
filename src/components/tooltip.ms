// react-native-paper Tooltip with Flutter Tooltip's timing: a long press shows `title` in a dark
// bubble just above the child, and the bubble leaves `leaveTouchDelay` ms after the release.

import { NeonEvent } from "../render/event";
import { Style, layerStyles } from "../render/style";
import { onCleanup } from "../core/cleanup";
import { Accessor, accessor, createSignal } from "../core/signal";
import { element } from "../macros/ui/element";
import { Show } from "../macros/ui/flow";
import { NeonNode } from "../render/node";
import { Host, HostNode } from "../render/hostTypes";
import { Pressable, Text, View } from "./primitives";

interface TooltipProps {
	title: Accessor<string>;
	enterTouchDelay?: Accessor<int32> | null;
	leaveTouchDelay?: Accessor<int32> | null;
	style?: Accessor<Style> | null;
	children?: NeonNode | null;
}

// paper Tooltip's touch defaults; 1500 ms is also Flutter Tooltip's showDuration.
export const TOOLTIP_ENTER_MS = 500;
export const TOOLTIP_LEAVE_MS = 1500;

// Flutter Tooltip: grey 700 at 90 %, 12-point white text, 32 points tall on touch.
const TOOLTIP_BUBBLE: Style = {
	position: "absolute",
	top: -40,
	left: 0,
	zIndex: 1000,
	minHeight: 32,
	justifyContent: "center",
	paddingLeft: 16,
	paddingRight: 16,
	paddingTop: 4,
	paddingBottom: 4,
	borderRadius: 4,
	backgroundColor: "#616161",
	opacity: 0.9,
};
const TOOLTIP_TEXT: Style = { color: "#ffffff", fontSize: 12 };

export function Tooltip(props: TooltipProps): NeonNode {
	const { title, enterTouchDelay, leaveTouchDelay } = props;
	const userStyle = props.style;
	const [open, setOpen] = createSignal(false);
	let hideId = -1;
	const cancelHide = (): void => {
		if (hideId >= 0) { clearTimeout(hideId); }
		hideId = -1;
	};
	const enter = accessor((): number => enterTouchDelay === null
		? TOOLTIP_ENTER_MS as float64
		: (enterTouchDelay as Accessor<int32>)() as float64);
	const leave = (): int32 => leaveTouchDelay === null
		? TOOLTIP_LEAVE_MS
		: (leaveTouchDelay as Accessor<int32>)();
	const show = (e: NeonEvent): void => {
		cancelHide();
		setOpen(true);
	};
	const release = (e: NeonEvent): void => {
		if (!open()) { return; }
		cancelHide();
		hideId = setTimeout((): void => {
			hideId = -1;
			setOpen(false);
		}, leave()) as int32;
	};
	const wrapper = accessor((): Style => {
		const base: Style = { zIndex: open() ? 1000 : 0 };
		return userStyle === null ? base : layerStyles([base, (userStyle as Accessor<Style>)()]);
	});
	const view = element(<Pressable style={wrapper} delayLongPress={enter()}
		onLongPress={show} onPressOut={release} accessibilityHint={title()}>
		{props.children}
		<Show when={open()}>
			<View style={TOOLTIP_BUBBLE}>
				<Text style={TOOLTIP_TEXT}>{title()}</Text>
			</View>
		</Show>
	</Pressable>);
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		onCleanup(cancelHide);
		view(host, parent, before);
	};
}
