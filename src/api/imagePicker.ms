import { PickReply, PickRequest, PickedAsset, captureServices } from "./captureServices";
import { Permissions, PermissionResponse } from "./permissions";

export type MediaType = "images" | "videos";
export type CameraType = "back" | "front";

export interface ImagePickerOptions {
	mediaTypes?: MediaType[] | null;
	allowsEditing?: boolean | null;
	aspect?: number[] | null;
	quality?: number | null;
	base64?: boolean | null;
	exif?: boolean | null;
	allowsMultipleSelection?: boolean | null;
	selectionLimit?: number | null;
	cameraType?: CameraType | null;
}

export interface ImagePickerAsset {
	uri: string;
	assetId: string | null;
	width: number;
	height: number;
	type: string;
	fileName: string | null;
	fileSize: number | null;
	mimeType: string | null;
	duration: number | null;
	base64: string | null;
}

export interface ImagePickerResult {
	canceled: boolean;
	assets: ImagePickerAsset[];
}

const NO_OPTIONS: ImagePickerOptions = {};

function mediaFlags(options: ImagePickerOptions, request: PickRequest): void {
	const types: MediaType[] = options.mediaTypes ?? [];
	if (types.length === 0) { return; }
	request.images = false;
	request.videos = false;
	for (const type of types) {
		const name: string = type;
		if (name === "images") { request.images = true; }
		else if (name === "videos") { request.videos = true; }
		else { throw new Error("ImagePicker: unknown media type " + name); }
	}
}

function pickRequest(options: ImagePickerOptions, camera: boolean): PickRequest {
	const quality = options.quality ?? 1;
	if (!(quality >= 0 && quality <= 1)) {
		throw new Error(`ImagePicker: quality must be between 0 and 1, got ${quality}`);
	}
	const limit = options.selectionLimit ?? 0;
	if (!(limit >= 0)) { throw new Error(`ImagePicker: selectionLimit must be 0 or more, got ${limit}`); }
	const facing: string = options.cameraType ?? "back";
	const request: PickRequest = {
		camera,
		images: true,
		videos: false,
		allowsEditing: options.allowsEditing ?? false,
		quality,
		base64: options.base64 ?? false,
		multiple: !camera && (options.allowsMultipleSelection ?? false),
		selectionLimit: limit as int32,
		cameraType: facing,
	};
	mediaFlags(options, request);
	return request;
}

function text(value: string): string | null {
	return value === "" ? null : value;
}

function amount(value: number): number | null {
	return value < 0 ? null : value;
}

function asset(picked: PickedAsset): ImagePickerAsset {
	return {
		uri: picked.uri,
		assetId: null,
		width: picked.width,
		height: picked.height,
		type: picked.type,
		fileName: text(picked.fileName),
		fileSize: amount(picked.fileSize),
		mimeType: text(picked.mimeType),
		duration: amount(picked.duration),
		base64: text(picked.base64),
	};
}

function result(reply: PickReply): ImagePickerResult {
	if (reply.error !== "") { throw new Error(reply.error); }
	const assets: ImagePickerAsset[] = [];
	for (const picked of reply.assets) { assets.push(asset(picked)); }
	return { canceled: reply.canceled, assets };
}

// Each throwing call is bound before `return`: on C an exception thrown by the operand of `return`
// in an async function is lost (compiler card 2026-10-08-async-return-of-a-throwing-call-loses-the-exception-on-c.md).
export class ImagePicker {
	static async launchImageLibraryAsync(options: ImagePickerOptions = NO_OPTIONS): Promise<ImagePickerResult> {
		const request = pickRequest(options, false);
		const picked = result(await captureServices("ImagePicker.launchImageLibraryAsync").pickMedia(request));
		return picked;
	}

	static async launchCameraAsync(options: ImagePickerOptions = NO_OPTIONS): Promise<ImagePickerResult> {
		const request = pickRequest(options, true);
		const permission = await Permissions.check("camera");
		if (!permission.granted) { throw new Error("ImagePicker.launchCameraAsync: Missing camera permission"); }
		const picked = result(await captureServices("ImagePicker.launchCameraAsync").pickMedia(request));
		return picked;
	}

	static async requestCameraPermissionsAsync(): Promise<PermissionResponse> {
		const answered = await Permissions.request("camera");
		return answered;
	}

	static async getCameraPermissionsAsync(): Promise<PermissionResponse> {
		const checked = await Permissions.check("camera");
		return checked;
	}

	static async requestMediaLibraryPermissionsAsync(): Promise<PermissionResponse> {
		return { status: "granted", granted: true, canAskAgain: true, expires: "never" };
	}

	static async getMediaLibraryPermissionsAsync(): Promise<PermissionResponse> {
		return { status: "granted", granted: true, canAskAgain: true, expires: "never" };
	}
}
