import { ActionSheetRequest, ActionSheetServices, installActionSheetServices } from "../../api/actionSheetServices";
import { AppEvent, FIELD, RECORD, appCall, onNativeAppEvent } from "./appBridge";

interface PendingSheet {
	id: int32;
	done: (index: int32) => void;
}

const sheets: PendingSheet[] = [];
let nextSheet: int32 = 1;

function remove(id: int32): PendingSheet | null {
	for (let i = 0; i < sheets.length; i += 1) {
		if (sheets[i].id === id) {
			const pending = sheets[i];
			sheets.splice(i, 1);
			return pending;
		}
	}
	return null;
}

function list(values: int32[]): string {
	return values.map((value: int32): string => value.toString()).join(",");
}

function showActionSheet(request: ActionSheetRequest): void {
	const id = nextSheet;
	nextSheet += 1;
	sheets.push({ id, done: request.done });
	let arg = [
		id.toString(), request.title, request.message, request.cancelButtonIndex.toString(),
		list(request.destructiveButtonIndices), list(request.disabledButtonIndices),
		request.tintColor, request.cancelButtonTintColor, request.disabledButtonTintColor, request.userInterfaceStyle,
	].join(FIELD);
	for (const option of request.options) { arg += RECORD + option; }
	appCall("actionsheet.show", arg);
}

function dismissActionSheet(): void {
	const dismissed = appCall("actionsheet.dismiss", "");
	if (dismissed !== "") { remove(parseInt(dismissed) as int32); }
}

function onActionSheetEvent(value: string): void {
	const fields = value.split(FIELD);
	const pending = remove(parseInt(fields[0]) as int32);
	if (pending !== null) { pending.done(parseInt(fields[1]) as int32); }
}

export const nativeActionSheetServices: ActionSheetServices = { showActionSheet, dismissActionSheet };

installActionSheetServices(nativeActionSheetServices);
onNativeAppEvent(AppEvent.ActionSheet, onActionSheetEvent);
