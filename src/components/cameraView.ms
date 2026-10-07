import { NeonEvent } from "../render/event";
import { Style, layerStyles } from "../render/style";
import { Accessor, createSignal } from "../core/signal";
import { onCleanup } from "../core/cleanup";
import { Host, HostNode } from "../render/hostTypes";
import { NeonNode, VAttr, VEvent, hostElement, evt, dynAttr } from "../render/node";
import { AccessibilityProps, accessibilityAttrs } from "./primitives";
import { Permissions, PermissionResponse } from "../api/permissions";
import { TextSlot } from "../api/replySlot";

export type CameraType = "back" | "front";
export type FlashMode = "off" | "on" | "auto";

export struct CameraMountError {
	message: string;
}

export interface CameraPictureOptions {
	quality?: number | null;
	base64?: boolean | null;
	skipProcessing?: boolean | null;
}

export interface CameraCapturedPicture {
	uri: string;
	width: number;
	height: number;
	format: string;
	base64: string | null;
}

export interface CameraViewProps extends AccessibilityProps {
	facing?: Accessor<CameraType> | null;
	flash?: Accessor<FlashMode> | null;
	active?: Accessor<boolean> | null;
	mirror?: Accessor<boolean> | null;
	style?: Accessor<Style> | null;
	ref?: ((handle: CameraViewHandle) => void) | null;
	onCameraReady?: (() => void) | null;
	onMountError?: ((error: CameraMountError) => void) | null;
	onLayout?: ((e: NeonEvent) => void) | null;
}

interface PendingPicture {
	id: int32;
	slot: TextSlot;
}

const FIELD = "\x1f";
let nextPicture: int32 = 1;

class CameraSlot {
	host: Host | null = null;
	node: HostNode | null = null;
	mounted: boolean = false;
	pictures: PendingPicture[] = [];

	command(name: string, argument: string): void {
		if (!this.mounted || this.host === null || this.node === null) {
			throw new Error(`CameraView.${name} was called while the CameraView is not mounted`);
		}
		(this.host as Host).setAttr(this.node as HostNode, "command", name + FIELD + argument);
	}

	settle(value: string): void {
		const cut = value.indexOf(FIELD);
		const id = parseInt(cut < 0 ? value : value.substring(0, cut)) as int32;
		for (let i = 0; i < this.pictures.length; i += 1) {
			if (this.pictures[i].id === id) {
				const pending = this.pictures[i];
				this.pictures.splice(i, 1);
				pending.slot.settle(cut < 0 ? "" : value.substring(cut + 1, value.length));
				return;
			}
		}
	}

	unmount(): void {
		this.mounted = false;
		const pending = this.pictures.slice(0, this.pictures.length);
		this.pictures.splice(0, this.pictures.length);
		for (const picture of pending) { picture.slot.settle("error" + FIELD + "the CameraView was unmounted before the picture was taken"); }
	}
}

function fieldNumber(fields: string[], at: int32): number {
	if (at >= fields.length || fields[at] === "") { return 0; }
	return parseFloat(fields[at]);
}

export function decodePicture(reply: string): CameraCapturedPicture {
	const fields = reply.split(FIELD);
	if (fields[0] === "error") {
		throw new Error("CameraView.takePictureAsync: " + (fields.length > 1 ? fields[1] : "the picture failed"));
	}
	if (fields[0] !== "ok" || fields.length < 4) { throw new Error("CameraView: the host sent a malformed picture: " + reply); }
	const base64 = fields.length > 4 && fields[4] !== "" ? fields[4] : null;
	return { uri: fields[1], width: fieldNumber(fields, 2), height: fieldNumber(fields, 3), format: "jpg", base64 };
}

export class CameraViewHandle {
	private slot: CameraSlot;

	constructor(slot: CameraSlot) {
		this.slot = slot;
	}

	async takePictureAsync(options: CameraPictureOptions = {}): Promise<CameraCapturedPicture> {
		const quality = options.quality ?? 1;
		if (!(quality >= 0 && quality <= 1)) {
			throw new Error(`CameraView.takePictureAsync: quality must be between 0 and 1, got ${quality}`);
		}
		const id = nextPicture;
		nextPicture += 1;
		const slot = new TextSlot();
		this.slot.command("takePicture", id.toString() + FIELD + quality.toString() + FIELD + ((options.base64 ?? false) ? "1" : "0"));
		this.slot.pictures.push({ id, slot });
		const reply = await slot.wait();
		const picture = decodePicture(reply);
		return picture;
	}

	pausePreview(): void { this.slot.command("pausePreview", ""); }
	resumePreview(): void { this.slot.command("resumePreview", ""); }
}

function choice(attrs: VAttr[], name: string, read: () => string): void {
	attrs.push(dynAttr(name, (): string | null => read()));
}

const CAMERA_BASE: Style = { overflow: "hidden", backgroundColor: "#000000" };

export function CameraView(props: CameraViewProps): NeonNode {
	const slot = new CameraSlot();
	const attrs: VAttr[] = [];
	const facing = props.facing;
	choice(attrs, "facing", (): string => {
		if (facing === null) { return "back"; }
		const value: string = (facing as Accessor<CameraType>)();
		return value;
	});
	const flash = props.flash;
	choice(attrs, "flash", (): string => {
		if (flash === null) { return "off"; }
		const value: string = (flash as Accessor<FlashMode>)();
		return value;
	});
	const active = props.active;
	choice(attrs, "active", (): string => active === null || (active as Accessor<boolean>)() ? "true" : "false");
	const mirror = props.mirror;
	choice(attrs, "mirror", (): string => mirror !== null && (mirror as Accessor<boolean>)() ? "true" : "false");
	accessibilityAttrs(props, attrs);
	const evts: VEvent[] = [];
	evts.push(evt("onPicture", (e: NeonEvent): void => { slot.settle(e.value); }));
	const ready = props.onCameraReady;
	if (ready !== null) { evts.push(evt("onCameraReady", (e: NeonEvent): void => { (ready as () => void)(); })); }
	const failed = props.onMountError;
	if (failed !== null) {
		evts.push(evt("onMountError", (e: NeonEvent): void => {
			(failed as (error: CameraMountError) => void)({ message: e.value });
		}));
	}
	if (props.onLayout !== null) { evts.push(evt("onLayout", props.onLayout as (e: NeonEvent) => void)); }
	const userStyle = props.style;
	const style = (): Style => userStyle === null ? CAMERA_BASE : layerStyles([CAMERA_BASE, (userStyle as () => Style)()]);
	const userRef = props.ref;
	const inner = hostElement("camera", attrs, evts, null, style, (node: HostNode): void => {
		slot.node = node;
		slot.mounted = true;
		onCleanup((): void => { slot.unmount(); });
		if (userRef !== null) { (userRef as (h: CameraViewHandle) => void)(new CameraViewHandle(slot)); }
	});
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		slot.host = host;
		inner(host, parent, before);
	};
}

export class Camera {
	static async requestCameraPermissionsAsync(): Promise<PermissionResponse> {
		const answered = await Permissions.request("camera");
		return answered;
	}

	static async getCameraPermissionsAsync(): Promise<PermissionResponse> {
		const checked = await Permissions.check("camera");
		return checked;
	}

	static async requestMicrophonePermissionsAsync(): Promise<PermissionResponse> {
		const answered = await Permissions.request("microphone");
		return answered;
	}

	static async getMicrophonePermissionsAsync(): Promise<PermissionResponse> {
		const checked = await Permissions.check("microphone");
		return checked;
	}
}

export function useCameraPermissions(): [Accessor<PermissionResponse | null>, () => Promise<PermissionResponse>] {
	const [permission, setPermission] = createSignal<PermissionResponse | null>(null);
	Permissions.check("camera").then((checked: PermissionResponse): void => { setPermission(checked); });
	const request = async (): Promise<PermissionResponse> => {
		const answered = await Permissions.request("camera");
		setPermission(answered);
		return answered;
	};
	return [permission, request];
}
