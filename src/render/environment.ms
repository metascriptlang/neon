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
