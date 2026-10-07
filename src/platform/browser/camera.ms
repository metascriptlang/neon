import { HostNode } from "../../render/hostTypes";
import { NeonEvent, neonEvent } from "../../render/event";
import { registerCss } from "../../render/sheet";

extern class CameraClassList {
	extern add(name: cstring): void;
	extern remove(name: cstring): void;
}

extern class HTMLVideoElement {
	classList: CameraClassList;
	extern setAttribute(name: cstring, value: cstring): void;
}


extern function createVideoElement(unused: int32): HTMLVideoElement from "(#, document.createElement('video'))";
extern function startCamera(video: HTMLVideoElement, facing: cstring, ready: () => void, failed: (message: string) => void): void from "((v, facing, ready, failed) => { if (v.__neonStream) { v.__neonStream.getTracks().forEach((t) => t.stop()); v.__neonStream = null; } if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) { failed('No camera is available on this device'); return; } const token = (v.__neonToken = (v.__neonToken || 0) + 1); navigator.mediaDevices.getUserMedia({ video: { facingMode: facing === 'front' ? 'user' : 'environment' }, audio: false }).then((s) => { if (v.__neonToken !== token) { s.getTracks().forEach((t) => t.stop()); return; } v.__neonStream = s; v.srcObject = s; const go = () => { const p = v.play(); if (p) p.then(() => ready(), (e) => failed(String((e && e.message) || e))); else ready(); }; if (v.readyState >= 1) go(); else v.addEventListener('loadedmetadata', go, { once: true }); }, (e) => { if (v.__neonToken !== token) return; const n = e && e.name; failed(n === 'NotAllowedError' || n === 'SecurityError' ? 'Camera permission not granted' : n === 'NotFoundError' || n === 'OverconstrainedError' || n === 'NotReadableError' ? 'No camera is available on this device' : String((e && e.message) || e)); }); })(#, #, #, #)";
extern function stopCamera(video: HTMLVideoElement): void from "((v) => { v.__neonToken = (v.__neonToken || 0) + 1; if (v.__neonStream) { v.__neonStream.getTracks().forEach((t) => t.stop()); v.__neonStream = null; } v.srcObject = null; })(#)";
extern function pauseCamera(video: HTMLVideoElement, paused: boolean): void from "((v, p) => { if (p) v.pause(); else if (v.srcObject) v.play(); })(#, #)";
extern function snapshotCamera(video: HTMLVideoElement, quality: number, mirror: boolean): string from "((v, q, m) => { const F = String.fromCharCode(31); if (!v.__neonStream || !v.videoWidth) return 'error' + F + 'the camera is not running'; const c = document.createElement('canvas'); c.width = v.videoWidth; c.height = v.videoHeight; const g = c.getContext('2d'); if (m) { g.translate(c.width, 0); g.scale(-1, 1); } g.drawImage(v, 0, 0); return ['ok', c.toDataURL('image/jpeg', q), c.width, c.height].join(F); })(#, #, #)";

interface CameraRoute {
	type: string;
	handler: (e: NeonEvent) => void;
}

const CAMERA_CSS = ".neon-camera{display:block;background:#000000;object-fit:cover}.neon-camera-mirror{transform:scaleX(-1)}";

class CameraState {
	el: HTMLVideoElement;
	routes: CameraRoute[] = [];
	facing: string = "back";
	active: boolean = true;
	mirror: boolean = false;
	running: boolean = false;
	released: boolean = false;
	scheduled: boolean = false;

	constructor(el: HTMLVideoElement) {
		this.el = el;
	}

	fire(type: string, value: string): void {
		if (this.released) { return; }
		for (const route of this.routes) {
			if (route.type !== type) { continue; }
			const e = neonEvent(type);
			e.timeStamp = performance.now();
			e.value = value;
			route.handler(e);
		}
	}
}

const cameras = new Map<HostNode, CameraState>();
let cssDone = false;

extern function queueMicrotask(callback: () => void): void;

function restart(state: CameraState): void {
	if (state.scheduled) { return; }
	state.scheduled = true;
	queueMicrotask((): void => {
		state.scheduled = false;
		if (state.released) { return; }
		state.running = false;
		if (!state.active) {
			stopCamera(state.el);
			return;
		}
		startCamera(state.el, state.facing, (): void => {
			state.running = true;
			state.fire("cameraready", "");
		}, (message: string): void => { state.fire("mounterror", message); });
	});
}

function mirrored(state: CameraState): boolean {
	return state.facing === "front" || state.mirror;
}

function placeMirror(state: CameraState): void {
	if (mirrored(state)) { state.el.classList.add("neon-camera-mirror"); } else { state.el.classList.remove("neon-camera-mirror"); }
}

export function createCameraNode(): HostNode {
	if (!cssDone) {
		registerCss("neon-camera", CAMERA_CSS);
		cssDone = true;
	}
	const el = createVideoElement(0);
	el.classList.add("neon-camera");
	el.setAttribute("playsinline", "");
	el.setAttribute("muted", "");
	el.setAttribute("autoplay", "");
	const state = new CameraState(el);
	const node = el as unknown as HostNode;
	cameras.set(node, state);
	restart(state);
	return node;
}

export function isCameraNode(node: HostNode): boolean {
	return cameras.has(node);
}

function command(state: CameraState, value: string): void {
	const fields = value.split("\x1f");
	const name = fields[0];
	if (name === "takePicture") {
		const id = fields[1];
		const quality = fields.length > 2 ? parseFloat(fields[2]) : 1;
		const base64 = fields.length > 3 && fields[3] === "1";
		const shot = snapshotCamera(state.el, quality, state.mirror).split("\x1f");
		if (shot[0] !== "ok") {
			queueMicrotask((): void => { state.fire("picture", id + "\x1f" + shot.join("\x1f")); });
			return;
		}
		const uri = shot[1];
		const encoded = base64 ? uri.substring(uri.indexOf(",") + 1, uri.length) : "";
		const reply = [id, "ok", uri, shot[2], shot[3], encoded].join("\x1f");
		queueMicrotask((): void => { state.fire("picture", reply); });
		return;
	}
	if (name === "pausePreview") { pauseCamera(state.el, true); return; }
	if (name === "resumePreview") { pauseCamera(state.el, false); return; }
	throw new Error(`CameraView: the browser host has no command "${name}"`);
}

export function writeCameraAttr(node: HostNode, name: string, value: string): boolean {
	if (!cameras.has(node)) { return false; }
	const state = cameras.get(node) as CameraState;
	if (name === "facing") {
		if (value !== state.facing) {
			state.facing = value;
			placeMirror(state);
			restart(state);
		}
		return true;
	}
	if (name === "active") {
		const active = value === "true";
		if (active !== state.active) {
			state.active = active;
			restart(state);
		}
		return true;
	}
	if (name === "mirror") {
		state.mirror = value === "true";
		placeMirror(state);
		return true;
	}
	if (name === "flash") { return true; }
	if (name === "command") {
		command(state, value);
		return true;
	}
	return false;
}

export function addCameraEvent(node: HostNode, type: string, handler: (e: NeonEvent) => void): boolean {
	if (!cameras.has(node) || type === "layout") { return false; }
	(cameras.get(node) as CameraState).routes.push({ type, handler });
	return true;
}

export function releaseCamera(node: HostNode): void {
	if (!cameras.has(node)) { return; }
	const state = cameras.get(node) as CameraState;
	state.released = true;
	stopCamera(state.el);
	cameras.delete(node);
}
