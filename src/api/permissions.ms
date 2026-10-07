import { PermissionReply, appServices } from "./services";
import { Alert, AlertButton } from "./alert";
import { TextSlot } from "./replySlot";

export type PermissionStatus = "granted" | "denied" | "undetermined";
export type PermissionName = "camera" | "microphone" | "location" | "notifications";

export interface PermissionResponse {
	status: PermissionStatus;
	granted: boolean;
	canAskAgain: boolean;
	expires: string;
}

function replyOrThrow(reply: PermissionReply): PermissionReply {
	if (reply.error !== "") { throw new Error(reply.error); }
	return reply;
}

function response(given: PermissionReply): PermissionResponse {
	const reply = replyOrThrow(given);
	return {
		status: reply.status as PermissionStatus,
		granted: reply.status === "granted",
		canAskAgain: reply.canAskAgain,
		expires: "never",
	};
}

export class Permissions {
	// Each throwing call is bound before `return`: on C an exception thrown by the operand of `return`
	// in an async function is lost (compiler card 2026-10-08-async-return-of-a-throwing-call-loses-the-exception-on-c.md).
	static async check(permission: PermissionName): Promise<PermissionResponse> {
		const name: string = permission;
		const checked = response(await appServices("Permissions.check").permissionStatus(name));
		return checked;
	}

	static async request(permission: PermissionName): Promise<PermissionResponse> {
		const name: string = permission;
		const answered = response(await appServices("Permissions.request").requestPermission(name));
		return answered;
	}
}

export type PermissionsAndroidResult = "granted" | "denied" | "never_ask_again";

export interface Rationale {
	title: string;
	message: string;
	buttonPositive?: string | null;
	buttonNegative?: string | null;
	buttonNeutral?: string | null;
}

export interface AndroidPermissionNames {
	READ_CALENDAR: string;
	WRITE_CALENDAR: string;
	CAMERA: string;
	READ_CONTACTS: string;
	WRITE_CONTACTS: string;
	GET_ACCOUNTS: string;
	ACCESS_FINE_LOCATION: string;
	ACCESS_COARSE_LOCATION: string;
	ACCESS_BACKGROUND_LOCATION: string;
	RECORD_AUDIO: string;
	READ_PHONE_STATE: string;
	CALL_PHONE: string;
	READ_CALL_LOG: string;
	WRITE_CALL_LOG: string;
	ADD_VOICEMAIL: string;
	USE_SIP: string;
	PROCESS_OUTGOING_CALLS: string;
	BODY_SENSORS: string;
	BODY_SENSORS_BACKGROUND: string;
	SEND_SMS: string;
	RECEIVE_SMS: string;
	READ_SMS: string;
	RECEIVE_WAP_PUSH: string;
	RECEIVE_MMS: string;
	READ_EXTERNAL_STORAGE: string;
	WRITE_EXTERNAL_STORAGE: string;
	BLUETOOTH_CONNECT: string;
	BLUETOOTH_SCAN: string;
	BLUETOOTH_ADVERTISE: string;
	ACCESS_MEDIA_LOCATION: string;
	ACCEPT_HANDOVER: string;
	ACTIVITY_RECOGNITION: string;
	ANSWER_PHONE_CALLS: string;
	READ_PHONE_NUMBERS: string;
	UWB_RANGING: string;
	POST_NOTIFICATIONS: string;
	NEARBY_WIFI_DEVICES: string;
	READ_MEDIA_IMAGES: string;
	READ_MEDIA_VIDEO: string;
	READ_MEDIA_AUDIO: string;
	READ_MEDIA_VISUAL_USER_SELECTED: string;
}

export interface AndroidPermissionResults {
	GRANTED: string;
	DENIED: string;
	NEVER_ASK_AGAIN: string;
}

const NO_RATIONALE: Rationale = { title: "", message: "" };

async function showRationale(rationale: Rationale): Promise<void> {
	const shown = new TextSlot();
	const buttons: AlertButton[] = [];
	const neutral = rationale.buttonNeutral ?? "";
	const negative = rationale.buttonNegative ?? "";
	if (neutral !== "") { buttons.push({ text: neutral, onPress: (): void => { shown.settle("neutral"); } }); }
	if (negative !== "") { buttons.push({ text: negative, onPress: (): void => { shown.settle("negative"); } }); }
	buttons.push({ text: rationale.buttonPositive ?? "OK", onPress: (): void => { shown.settle("positive"); } });
	Alert.alert(rationale.title, rationale.message, buttons, { onDismiss: (): void => { shown.settle("dismissed"); } });
	await shown.wait();
}

export class PermissionsAndroid {
	static PERMISSIONS: AndroidPermissionNames = {
		READ_CALENDAR: "android.permission.READ_CALENDAR",
		WRITE_CALENDAR: "android.permission.WRITE_CALENDAR",
		CAMERA: "android.permission.CAMERA",
		READ_CONTACTS: "android.permission.READ_CONTACTS",
		WRITE_CONTACTS: "android.permission.WRITE_CONTACTS",
		GET_ACCOUNTS: "android.permission.GET_ACCOUNTS",
		ACCESS_FINE_LOCATION: "android.permission.ACCESS_FINE_LOCATION",
		ACCESS_COARSE_LOCATION: "android.permission.ACCESS_COARSE_LOCATION",
		ACCESS_BACKGROUND_LOCATION: "android.permission.ACCESS_BACKGROUND_LOCATION",
		RECORD_AUDIO: "android.permission.RECORD_AUDIO",
		READ_PHONE_STATE: "android.permission.READ_PHONE_STATE",
		CALL_PHONE: "android.permission.CALL_PHONE",
		READ_CALL_LOG: "android.permission.READ_CALL_LOG",
		WRITE_CALL_LOG: "android.permission.WRITE_CALL_LOG",
		ADD_VOICEMAIL: "com.android.voicemail.permission.ADD_VOICEMAIL",
		USE_SIP: "android.permission.USE_SIP",
		PROCESS_OUTGOING_CALLS: "android.permission.PROCESS_OUTGOING_CALLS",
		BODY_SENSORS: "android.permission.BODY_SENSORS",
		BODY_SENSORS_BACKGROUND: "android.permission.BODY_SENSORS_BACKGROUND",
		SEND_SMS: "android.permission.SEND_SMS",
		RECEIVE_SMS: "android.permission.RECEIVE_SMS",
		READ_SMS: "android.permission.READ_SMS",
		RECEIVE_WAP_PUSH: "android.permission.RECEIVE_WAP_PUSH",
		RECEIVE_MMS: "android.permission.RECEIVE_MMS",
		READ_EXTERNAL_STORAGE: "android.permission.READ_EXTERNAL_STORAGE",
		WRITE_EXTERNAL_STORAGE: "android.permission.WRITE_EXTERNAL_STORAGE",
		BLUETOOTH_CONNECT: "android.permission.BLUETOOTH_CONNECT",
		BLUETOOTH_SCAN: "android.permission.BLUETOOTH_SCAN",
		BLUETOOTH_ADVERTISE: "android.permission.BLUETOOTH_ADVERTISE",
		ACCESS_MEDIA_LOCATION: "android.permission.ACCESS_MEDIA_LOCATION",
		ACCEPT_HANDOVER: "android.permission.ACCEPT_HANDOVER",
		ACTIVITY_RECOGNITION: "android.permission.ACTIVITY_RECOGNITION",
		ANSWER_PHONE_CALLS: "android.permission.ANSWER_PHONE_CALLS",
		READ_PHONE_NUMBERS: "android.permission.READ_PHONE_NUMBERS",
		UWB_RANGING: "android.permission.UWB_RANGING",
		POST_NOTIFICATIONS: "android.permission.POST_NOTIFICATIONS",
		NEARBY_WIFI_DEVICES: "android.permission.NEARBY_WIFI_DEVICES",
		READ_MEDIA_IMAGES: "android.permission.READ_MEDIA_IMAGES",
		READ_MEDIA_VIDEO: "android.permission.READ_MEDIA_VIDEO",
		READ_MEDIA_AUDIO: "android.permission.READ_MEDIA_AUDIO",
		READ_MEDIA_VISUAL_USER_SELECTED: "android.permission.READ_MEDIA_VISUAL_USER_SELECTED",
	};

	static RESULTS: AndroidPermissionResults = {
		GRANTED: "granted",
		DENIED: "denied",
		NEVER_ASK_AGAIN: "never_ask_again",
	};

	static async check(permission: string): Promise<boolean> {
		return await appServices("PermissionsAndroid.check").androidPermissionGranted(permission);
	}

	// Promise<string>, not Promise<PermissionsAndroidResult>: awaiting a literal-union promise dies at clang
	// (compiler card 2026-10-08-await-of-a-string-literal-union-promise-dies-at-clang.md). The rationale
	// defaults to an empty one rather than null: on JS a literal passed as `Rationale | null` keeps its
	// absent fields undefined (card 2026-10-06-js-optional-fields-through-nullable-constructor.md).
	static async request(permission: string, rationale: Rationale = NO_RATIONALE): Promise<string> {
		const services = appServices("PermissionsAndroid.request");
		if (rationale.title !== "" && (await services.androidShouldShowRationale(permission))) {
			await showRationale(rationale);
		}
		const results = await services.androidRequestPermissions([permission]);
		const result = replyOrThrow(results[0]);
		return result.status;
	}

	static async requestMultiple(permissions: string[]): Promise<Map<string, string>> {
		const results = await appServices("PermissionsAndroid.requestMultiple").androidRequestPermissions(permissions);
		const byPermission = new Map<string, string>();
		for (let i = 0; i < permissions.length; i += 1) {
			byPermission.set(permissions[i], replyOrThrow(results[i]).status);
		}
		return byPermission;
	}
}
