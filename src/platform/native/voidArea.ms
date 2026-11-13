import { registerNativeElement } from "./elements";
import { batched, installVoidAreas } from "./host";
import { niRequestFrame } from "./bridge.h";
import {
	niVoidAreaCreate, niVoidAreaLayer, niLastVoidAreaView, niLastVoidAreaEvent,
	niLastVoidAreaWidth, niLastVoidAreaHeight, niLastVoidAreaScale, niLastVoidAreaTouchCount,
	niLastVoidAreaTouchId, niLastVoidAreaTouchX, niLastVoidAreaTouchY, niLastVoidAreaTouchChanged,
} from "./voidArea.h";
import { VoidArea } from "../../render/hostTypes";
import { AreaKeyMod } from "../../render/voidAreaHandle";
import { embedRegister, viewCreate, viewResize, viewFrame, viewDestroy, currentView, gfxSetup, ViewId, ViewInvalid } from "../../../../void/src/host/gpu";
import { setup2d, preparePipelines } from "../../../../void/src/void2d/draw";
import { BlendMode } from "../../../../void/src/gpu/state";
import { commit } from "../../../../void/src/gpu/door";
import { FontId } from "../../../../void/src/void2d/font";
import { isDirty } from "../../../../void/src/void2d/scene";
import { AppEventType, AppTouch } from "../../../../void/src/host/window";
import { WindowArea, openWindowArea, drawArea, deliverAreaResize } from "../void/windowHost";
import { TouchGesture } from "../sokol/touch";
import { canvasFont } from "../sokol/canvasFont";

when (ios) {
	@compile("../ios/voidArea.m", "-fobjc-arc");
}

extern function niSetVoidAreaHandler(handler: () => void): void;

export interface VoidAreaFont {
	font: string;
	fontFamily: string | null;
	fontBytes: uint8[] | null;
	defaultFontBytes: uint8[] | null;
}

interface LoadedFont {
	font: FontId;
	family: string;
}

interface NativeArea {
	view: Ptr<void>;
	gpu: ViewId;
	area: WindowArea;
	touch: TouchGesture;
	owed: boolean;
}

const areas: NativeArea[] = [];
let retired: ViewId[] = [];
let fontOptions: VoidAreaFont = { font: "assets/font.ttf", fontFamily: null, fontBytes: null, defaultFontBytes: null };
let loaded: LoadedFont | null = null;

export function setVoidAreaFont(options: VoidAreaFont): void {
	if (loaded !== null) { throw new Error(`setVoidAreaFont(${options.font}) after the first <Void> opened with ${fontOptions.font}`); }
	fontOptions = options;
}

function areaFont(): LoadedFont {
	if (loaded !== null) { return loaded as LoadedFont; }
	const font = canvasFont(fontOptions.font, fontOptions.fontFamily, fontOptions.fontBytes, fontOptions.defaultFontBytes);
	if (!font.ok) { throw new Error(`native Void area: ${font.error}`); }
	const family = fontOptions.fontFamily !== null ? fontOptions.fontFamily as string : fontOptions.font;
	const face: LoadedFont = { font: font.value, family };
	loaded = face;
	return face;
}

function areaOfView(view: Ptr<void>): NativeArea | null {
	for (const a of areas) {
		if (a.view === view) { return a; }
	}
	return null;
}

function owe(view: Ptr<void>): void {
	const owner = areaOfView(view);
	if (owner === null) { return; }
	owner.owed = true;
	niRequestFrame();
}

function initGpu(): void {
	gfxSetup();
	setup2d();
	preparePipelines([BlendMode.Alpha]);
}

function drawCurrent(): void {
	const view = currentView();
	for (const owner of areas) {
		if (owner.gpu !== view) { continue; }
		owner.owed = false;
		if (!drawArea(owner.area)) { commit(); }
		return;
	}
	throw new Error(`native Void area: Void asked to draw view ${view}, which no area owns`);
}

function drawOwed(): void {
	for (const owner of areas.slice()) {
		if (owner.gpu === ViewInvalid || !(owner.owed || owner.area.vh.scene.isDirty())) { continue; }
		if (!viewFrame(owner.gpu)) { niRequestFrame(); }
	}
	if (retired.length > 0) {
		const due = retired;
		retired = [];
		for (const view of due) { viewDestroy(view); }
	}
}

function open(view: Ptr<void>): VoidArea {
	const face = areaFont();
	return openWindowArea({
		name: "native Void area",
		font: face.font,
		family: face.family,
		pixelWidth: (): int32 => 0 as int32,
		pixelHeight: (): int32 => 0 as int32,
		requestFrame: (): void => { owe(view); },
		dirty: (): void => { owe(view); },
		setImeRect: (pixelX: int32, pixelY: int32, pixelW: int32, pixelH: int32): void => {},
		opened: (area: WindowArea): void => {
			areas.push({ view, gpu: ViewInvalid, area, touch: new TouchGesture(area), owed: true });
		},
		released: (area: WindowArea): void => {
			const owner = areaOfView(view);
			if (owner === null) { return; }
			areas.splice(areas.indexOf(owner), 1);
			owner.touch.stop();
			if (owner.gpu === ViewInvalid) { return; }
			if (currentView() === owner.gpu) { retired.push(owner.gpu); } else { viewDestroy(owner.gpu); }
		},
	});
}

function resize(owner: NativeArea): void {
	const width = niLastVoidAreaWidth();
	const height = niLastVoidAreaHeight();
	const scale = niLastVoidAreaScale();
	deliverAreaResize(owner.area, width, height, scale as float64);
	if (owner.gpu === ViewInvalid) {
		owner.gpu = viewCreate(niVoidAreaLayer(owner.view), width, height, scale);
	} else {
		viewResize(owner.gpu, width, height, scale);
	}
	owe(owner.view);
}

function touchType(event: int32): AppEventType {
	return match (event) {
		1 => AppEventType.TouchesBegan,
		2 => AppEventType.TouchesMoved,
		3 => AppEventType.TouchesEnded,
		4 => AppEventType.TouchesCancelled,
		_ => { throw new Error(`native Void area: event ${event} is neither a resize nor a touch`); },
	};
}

function touches(): AppTouch[] {
	const out: AppTouch[] = [];
	for (let i: int32 = 0; i < niLastVoidAreaTouchCount(); i++) {
		out.push({
			id: niLastVoidAreaTouchId(i),
			x: niLastVoidAreaTouchX(i),
			y: niLastVoidAreaTouchY(i),
			changed: niLastVoidAreaTouchChanged(i) !== 0,
		});
	}
	return out;
}

function onAreaEvent(): void {
	const owner = areaOfView(niLastVoidAreaView() as Ptr<void>);
	if (owner === null) { return; }
	const event = niLastVoidAreaEvent();
	batched((): void => {
		if (event === 0) {
			resize(owner as NativeArea);
			return;
		}
		(owner as NativeArea).touch.deliver(touchType(event), touches(), 0 as BitSet<AreaKeyMod>);
	});
}

registerNativeElement("void", { create: (): Ptr<void> | null => niVoidAreaCreate(), sizesItself: false });
embedRegister(initGpu, drawCurrent);
niSetVoidAreaHandler(onAreaEvent);
installVoidAreas({ open, frame: drawOwed });
