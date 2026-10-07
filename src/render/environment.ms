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

const [windowWidth, setWindowWidth] = createSignal<number>(0);
const [windowHeight, setWindowHeight] = createSignal<number>(0);
const [keyboardHeight, setKeyboardHeight] = createSignal<number>(0);
const [dark, setDark] = createSignal<boolean>(false);

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

const [insetTop, setInsetTop] = createSignal<number>(0);
const [insetRight, setInsetRight] = createSignal<number>(0);
const [insetBottom, setInsetBottom] = createSignal<number>(0);
const [insetLeft, setInsetLeft] = createSignal<number>(0);

export function useSafeAreaInsets(): Accessor<EdgeInsets> {
	return accessor((): EdgeInsets => ({ top: insetTop(), right: insetRight(), bottom: insetBottom(), left: insetLeft() }));
}

export function publishSafeArea(top: number, right: number, bottom: number, left: number): void {
	if (insetTop() !== top) { setInsetTop(top); }
	if (insetRight() !== right) { setInsetRight(right); }
	if (insetBottom() !== bottom) { setInsetBottom(bottom); }
	if (insetLeft() !== left) { setInsetLeft(left); }
}
