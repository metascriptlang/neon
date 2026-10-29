import { ActionSheetRequest, actionSheetServices } from "./actionSheetServices";
import { INT32_MAX, checkedInt32 } from "./hostCodec";

when (ios) {
	import "../platform/native/actionSheet";
}

// `anchor` is accepted and the sheet is centered, as RN does without one.
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

const API = "ActionSheetIOS.showActionSheetWithOptions";

function indices(field: string, values: number[]): int32[] {
	const result: int32[] = [];
	for (let i = 0; i < values.length; i += 1) {
		result.push(checkedInt32(API, `${field}[${i}]`, values[i], 0, INT32_MAX));
	}
	return result;
}

function destructive(value: number | number[] | null): int32[] {
	if (value === null) { return []; }
	if (typeof value === "number") { return indices("destructiveButtonIndex", [value]); }
	return indices("destructiveButtonIndex", value);
}

export class ActionSheetIOS {
	static showActionSheetWithOptions(options: ActionSheetIOSOptions, callback: (buttonIndex: number) => void): void {
		const disabled = indices("disabledButtonIndices", options.disabledButtonIndices ?? []);
		const cancel = options.cancelButtonIndex ?? null;
		const cancelIndex = cancel === null ? -1 : checkedInt32(API, "cancelButtonIndex", cancel, 0, INT32_MAX);
		for (const index of disabled) {
			if (index >= options.options.length) {
				throw new Error(
					`${API}: index ${index} from disabledButtonIndices is out of bounds, the maximum is ${options.options.length - 1}`,
				);
			}
		}
		const request: ActionSheetRequest = {
			title: options.title ?? "",
			message: options.message ?? "",
			options: options.options,
			cancelButtonIndex: cancelIndex,
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
