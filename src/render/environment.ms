import { Accessor, accessor, batch, createSignal } from "../core/signal";

export type ColorScheme = "light" | "dark";

export interface WindowDimensions {
	width: number;
	height: number;
}

export interface KeyboardMetrics {
	visible: boolean;
	height: number;
}

const windowWidthSignal = createSignal<number>(0);
const windowWidth = windowWidthSignal[0];
const setWindowWidth = windowWidthSignal[1];
const windowHeightSignal = createSignal<number>(0);
const windowHeight = windowHeightSignal[0];
const setWindowHeight = windowHeightSignal[1];
const keyboardHeightSignal = createSignal<number>(0);
const keyboardHeight = keyboardHeightSignal[0];
const setKeyboardHeight = keyboardHeightSignal[1];
const darkSignal = createSignal<boolean>(false);
const dark = darkSignal[0];
const setDark = darkSignal[1];

export function useWindowDimensions(): Accessor<WindowDimensions> {
	return accessor((): WindowDimensions => ({ width: windowWidth(), height: windowHeight() }));
}

export function useColorScheme(): Accessor<ColorScheme> {
	return accessor((): ColorScheme => dark() ? "dark" : "light");
}

export function useKeyboard(): Accessor<KeyboardMetrics> {
	return accessor((): KeyboardMetrics => ({ visible: keyboardHeight() > 0, height: keyboardHeight() }));
}

export function publishWindow(width: number, height: number): void {
	batch((): void => {
		if (windowWidth() !== width) { setWindowWidth(width); }
		if (windowHeight() !== height) { setWindowHeight(height); }
	});
}

export function publishKeyboard(height: number): void {
	if (keyboardHeight() !== height) { setKeyboardHeight(height); }
}

export function publishColorScheme(scheme: ColorScheme): void {
	const next = scheme === "dark";
	if (dark() !== next) { setDark(next); }
}

// How far the unsafe areas (status bar, notch, home indicator) reach into the
// root a host renders into, per edge.
export interface EdgeInsets {
	top: number;
	right: number;
	bottom: number;
	left: number;
}

const insetTopSignal = createSignal<number>(0);
const insetTop = insetTopSignal[0];
const setInsetTop = insetTopSignal[1];
const insetRightSignal = createSignal<number>(0);
const insetRight = insetRightSignal[0];
const setInsetRight = insetRightSignal[1];
const insetBottomSignal = createSignal<number>(0);
const insetBottom = insetBottomSignal[0];
const setInsetBottom = insetBottomSignal[1];
const insetLeftSignal = createSignal<number>(0);
const insetLeft = insetLeftSignal[0];
const setInsetLeft = insetLeftSignal[1];

export function useSafeAreaInsets(): Accessor<EdgeInsets> {
	return accessor((): EdgeInsets => ({ top: insetTop(), right: insetRight(), bottom: insetBottom(), left: insetLeft() }));
}

export function publishSafeArea(top: number, right: number, bottom: number, left: number): void {
	batch((): void => {
		if (insetTop() !== top) { setInsetTop(top); }
		if (insetRight() !== right) { setInsetRight(right); }
		if (insetBottom() !== bottom) { setInsetBottom(bottom); }
		if (insetLeft() !== left) { setInsetLeft(left); }
	});
}
