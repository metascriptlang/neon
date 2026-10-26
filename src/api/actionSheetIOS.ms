import { ActionSheetRequest, actionSheetServices } from "./actionSheetServices";

when (ios) {
	import "../platform/native/actionSheet";
}

// Colors are CSS strings, as everywhere in Neon; `anchor` is accepted and the sheet is centered, as RN does without one.
// Source: react-native 693e9628e8c, Libraries/ActionSheetIOS/ActionSheetIOS.js:55-130, React/CoreModules/RCTActionSheetManager.mm:76-230.
export interface ActionSheetIOSOptions {
	title?: string | null;
	message?: string | null;
	options: string[];
	destructiveButtonIndex?: number | number[] | null;
	cancelButtonIndex?: number | null;
	anchor?: number | null;
	tintColor?: string | null;
	cancelButtonTintColor?: string | null;
	disabledButtonTintColor?: string | null;
	userInterfaceStyle?: string | null;
	disabledButtonIndices?: number[] | null;
}

function indices(values: number[]): int32[] {
	const result: int32[] = [];
	for (const value of values) { result.push(value as int32); }
	return result;
}

function destructive(value: number | number[] | null): int32[] {
	if (value === null) { return []; }
	if (typeof value === "number") { return [value as int32]; }
	return indices(value);
}

export class ActionSheetIOS {
	static showActionSheetWithOptions(options: ActionSheetIOSOptions, callback: (buttonIndex: number) => void): void {
		const disabled = indices(options.disabledButtonIndices ?? []);
		for (const index of disabled) {
			if (index < 0 || index >= options.options.length) {
				throw new Error(
					`ActionSheetIOS.showActionSheetWithOptions: index ${index} from disabledButtonIndices is out of bounds, the maximum is ${options.options.length - 1}`,
				);
			}
		}
		const request: ActionSheetRequest = {
			title: options.title ?? "",
			message: options.message ?? "",
			options: options.options,
			cancelButtonIndex: (options.cancelButtonIndex ?? -1) as int32,
			destructiveButtonIndices: destructive(options.destructiveButtonIndex),
			disabledButtonIndices: disabled,
			tintColor: options.tintColor ?? "",
			cancelButtonTintColor: options.cancelButtonTintColor ?? "",
			disabledButtonTintColor: options.disabledButtonTintColor ?? "",
			userInterfaceStyle: options.userInterfaceStyle ?? "",
			done: (index: int32): void => { callback(index); },
		};
		actionSheetServices("ActionSheetIOS.showActionSheetWithOptions").showActionSheet(request);
	}

	static dismissActionSheet(): void {
		actionSheetServices("ActionSheetIOS.dismissActionSheet").dismissActionSheet();
	}
}
