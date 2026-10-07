// react-native-toast-message: `<ToastHost />` placed once, last, at the root of the app, and an
// imperative `Toast.show(...)` / `Toast.hide()` that reaches it through a module signal. The look
// is the Android toast: a dark pill near the bottom, so `position` defaults to "bottom".

import { Style, layerStyles } from "../render/style";
import { createEffect } from "../core/effect";
import { onCleanup } from "../core/cleanup";
import { Accessor, accessor, createSignal } from "../core/signal";
import { element } from "../macros/ui/element";
import { Show } from "../macros/ui/flow";
import { NeonNode } from "../render/node";
import { Host, HostNode } from "../render/hostTypes";
import { Text, View } from "./primitives";

export type ToastType = "success" | "error" | "info";
export type ToastPosition = "top" | "bottom";

export interface ToastOptions {
	text1: string;
	text2?: string | null;
	type?: ToastType | null;
	position?: ToastPosition | null;
	visibilityTime?: int32 | null;
	autoHide?: boolean | null;
}

export interface ToastShown {
	text1: string;
	text2: string;
	type: ToastType;
	position: ToastPosition;
	visibilityTime: int32;
	autoHide: boolean;
}

export interface ToastApi {
	show: (options: ToastOptions) => void;
	hide: () => void;
}

// react-native-toast-message's defaults: 4 s on screen, 40 points from the edge.
export const TOAST_VISIBILITY_MS = 4000;
const TOAST_OFFSET = 40;

const TOAST_NONE: ToastShown = {
	text1: "",
	text2: "",
	type: "info",
	position: "bottom",
	visibilityTime: TOAST_VISIBILITY_MS,
	autoHide: false,
};

const [shown, setShown] = createSignal<ToastShown | null>(null);

function showToast(options: ToastOptions): void {
	const {
		text2 = "",
		type = "info",
		position = "bottom",
		visibilityTime = TOAST_VISIBILITY_MS,
		autoHide = true,
	} = options;
	setShown({
		text1: options.text1,
		text2: text2 as string,
		type: type as ToastType,
		position: position as ToastPosition,
		visibilityTime: visibilityTime as int32,
		autoHide: autoHide as boolean,
	});
}

function hideToast(): void {
	setShown(null);
}

export const Toast: ToastApi = { show: showToast, hide: hideToast };

// The toast on screen, or null: for a host that draws its own toast from the same calls.
export function currentToast(): ToastShown | null {
	return shown();
}

function dotColor(type: ToastType): string {
	return match (type) {
		"success" => "#4caf50",
		"error" => "#f44336",
		_ => "#2196f3",
	};
}

const TOAST_PILL: Style = {
	flexDirection: "row",
	alignItems: "center",
	gap: 10,
	maxWidth: 360,
	paddingLeft: 20,
	paddingRight: 20,
	paddingTop: 12,
	paddingBottom: 12,
	borderRadius: 24,
	backgroundColor: "#323232",
};
const TOAST_DOT: Style = { width: 8, height: 8, borderRadius: 4 };
const TOAST_BODY: Style = { flexShrink: 1, flexDirection: "column", gap: 2 };
const TOAST_TEXT1: Style = { color: "#ffffff", fontSize: 14, fontWeight: "bold" };
const TOAST_TEXT2: Style = { color: "#e0e0e0", fontSize: 13 };

interface ToastHostProps {
	style?: Accessor<Style> | null;
}

export function ToastHost(props: ToastHostProps): NeonNode {
	const userStyle = props.style;
	// A binding inside the Show can run once more while the toast is being hidden.
	const read = (): ToastShown => {
		const t = shown();
		return t === null ? TOAST_NONE : t as ToastShown;
	};
	const layer = accessor((): Style => {
		const top = read().position === "top";
		const base: Style = {
			position: "absolute",
			left: 16,
			right: 16,
			top: top ? TOAST_OFFSET : null,
			bottom: top ? null : TOAST_OFFSET,
			zIndex: 1000,
			alignItems: "center",
		};
		return userStyle === null ? base : layerStyles([base, (userStyle as Accessor<Style>)()]);
	});
	const dot = accessor((): Style => ({ ...TOAST_DOT, backgroundColor: dotColor(read().type) }));
	const label = accessor((): string => {
		const t = read();
		return t.text2 === "" ? t.text1 : t.text1 + ", " + t.text2;
	});
	const view = element(<Show when={shown() !== null}>
		<View style={layer}>
			<View style={TOAST_PILL} accessibilityRole="alert" accessibilityLabel={label()}>
				<View style={dot} />
				<View style={TOAST_BODY}>
					<Text style={TOAST_TEXT1}>{read().text1}</Text>
					<Show when={read().text2 !== ""}>
						<Text style={TOAST_TEXT2}>{read().text2}</Text>
					</Show>
				</View>
			</View>
		</View>
	</Show>);
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		createEffect((): void => {
			const t = shown();
			if (t === null || !(t as ToastShown).autoHide) { return; }
			const id = setTimeout((): void => {
				if (shown() === t) { setShown(null); }
			}, (t as ToastShown).visibilityTime) as int32;
			onCleanup((): void => { clearTimeout(id); });
		});
		view(host, parent, before);
	};
}
