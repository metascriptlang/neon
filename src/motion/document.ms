export const MOTION_VERSION: int32 = 1;

export enum ValueKind {
	Number,
	Color,
}

export struct MotionColor {
	r: float64;
	g: float64;
	b: float64;
	a: float64;
}

export struct MotionValue {
	kind: ValueKind;
	number: float64;
	color: MotionColor;
}

export struct MotionHandles {
	leftX: float64;
	leftY: float64;
	rightX: float64;
	rightY: float64;
}

export struct MotionKeyframe {
	id: string;
	time: float64;
	value: MotionValue;
	handles: MotionHandles;
	connectedRight: boolean;
}

export struct MotionTrack {
	slot: string;
	property: string;
	kind: ValueKind;
	keyframes: MotionKeyframe[];
}

export struct MotionSlotMapping {
	from: string;
	to: string;
}

export struct MotionPlacement {
	clip: string;
	start: float64;
	rate: float64;
	slots: MotionSlotMapping[];
}

export struct MotionClip {
	id: string;
	duration: float64;
	tracks: MotionTrack[];
	placements: MotionPlacement[];
}

export struct MotionDocument {
	version: int32;
	root: string;
	clips: MotionClip[];
}

export function numberValue(number: float64): MotionValue {
	return { kind: ValueKind.Number, number, color: { r: 0, g: 0, b: 0, a: 0 } };
}

export function colorValue(r: float64, g: float64, b: float64, a: float64): MotionValue {
	return { kind: ValueKind.Color, number: 0, color: { r, g, b, a } };
}

export function linearKeyframe(id: string, time: float64, value: float64): MotionKeyframe {
	return {
		id,
		time,
		value: numberValue(value),
		handles: { leftX: 2.0 / 3.0, leftY: 2.0 / 3.0, rightX: 1.0 / 3.0, rightY: 1.0 / 3.0 },
		connectedRight: true,
	};
}

function fail(message: string): never {
	throw new Error("motion: " + message);
}

function requireFinite(value: float64, what: string): void {
	if (!Number.isFinite(value)) { fail("non-finite " + what); }
}

function requireHandleX(x: float64, where: string): void {
	requireFinite(x, "handle in " + where);
	if (x < 0 || x > 1) { fail("handle x must be in [0, 1] in " + where); }
}

function checkKeyframe(keyframe: MotionKeyframe, kind: ValueKind, where: string): void {
	requireFinite(keyframe.time, "keyframe time in " + where);
	if (keyframe.value.kind !== kind) { fail("value kind mismatch for keyframe " + keyframe.id + " in " + where); }
	if (kind === ValueKind.Number) {
		requireFinite(keyframe.value.number, "keyframe value in " + where);
	} else {
		const color = keyframe.value.color;
		for (const component of [color.r, color.g, color.b, color.a]) {
			requireFinite(component, "colour component in " + where);
			if (component < 0 || component > 1) { fail("colour component must be in [0, 1] in " + where); }
		}
	}
	const handles = keyframe.handles;
	requireFinite(handles.leftY, "handle in " + where);
	requireFinite(handles.rightY, "handle in " + where);
	requireHandleX(handles.leftX, where);
	requireHandleX(handles.rightX, where);
}

function checkTrack(track: MotionTrack, where: string): void {
	const name = where + " track " + track.slot + "." + track.property;
	if (track.keyframes.length === 0) { fail("no keyframes in " + name); }
	const ids: string[] = [];
	for (let i: int32 = 0; i < track.keyframes.length; i += 1) {
		const keyframe = track.keyframes[i];
		checkKeyframe(keyframe, track.kind, name);
		if (ids.includes(keyframe.id)) { fail("duplicate keyframe id " + keyframe.id + " in " + name); }
		ids.push(keyframe.id);
		if (i > 0) {
			const previous = track.keyframes[i - 1].time;
			if (keyframe.time === previous) { fail("duplicate keyframe time in " + name); }
			if (keyframe.time < previous) { fail("keyframes not sorted by time in " + name); }
		}
	}
}

function checkPlacement(placement: MotionPlacement, where: string): void {
	requireFinite(placement.start, "placement start in " + where);
	requireFinite(placement.rate, "placement rate in " + where);
	if (placement.rate <= 0) { fail("placement rate must be positive in " + where); }
	const from: string[] = [];
	for (const mapping of placement.slots) {
		if (mapping.from === "" || mapping.to === "" || from.includes(mapping.from)) {
			fail("slot mapping needs distinct non-empty names in " + where);
		}
		from.push(mapping.from);
	}
}

function indexOfClip(doc: MotionDocument, id: string): int32 {
	for (let i: int32 = 0; i < doc.clips.length; i += 1) {
		if (doc.clips[i].id === id) { return i; }
	}
	return -1;
}

export function findClip(doc: MotionDocument, id: string): MotionClip {
	const index = indexOfClip(doc, id);
	if (index < 0) { fail("unknown clip " + id); }
	return doc.clips[index];
}

function checkWindow(placement: MotionPlacement, child: MotionClip, parent: MotionClip): void {
	const end = Math.round((placement.start + child.duration / placement.rate) * 1e8) / 1e8;
	if (placement.start < 0 || end > parent.duration) {
		fail("placement of clip " + child.id + " must lie inside the duration of clip " + parent.id);
	}
}

function checkAcyclic(doc: MotionDocument, id: string, path: string[]): void {
	if (path.includes(id)) { fail("placement cycle through clip " + id); }
	path.push(id);
	for (const placement of doc.clips[indexOfClip(doc, id)].placements) {
		checkAcyclic(doc, placement.clip, path);
	}
	path.pop();
}

export function validate(doc: MotionDocument): void {
	if (doc.version !== MOTION_VERSION) { fail("unsupported version " + doc.version.toString()); }
	const ids: string[] = [];
	for (const clip of doc.clips) {
		if (ids.includes(clip.id)) { fail("duplicate clip id " + clip.id); }
		ids.push(clip.id);
	}
	if (indexOfClip(doc, doc.root) < 0) { fail("unknown root clip " + doc.root); }
	for (const clip of doc.clips) {
		const where = "clip " + clip.id;
		requireFinite(clip.duration, "duration of " + where);
		if (clip.duration <= 0) { fail("duration of " + where + " must be positive"); }
		const targets: string[] = [];
		for (const track of clip.tracks) {
			const target = track.slot + "\n" + track.property;
			if (targets.includes(target)) { fail("duplicate track " + track.slot + "." + track.property + " in " + where); }
			targets.push(target);
			checkTrack(track, where);
		}
		for (const placement of clip.placements) {
			if (indexOfClip(doc, placement.clip) < 0) { fail("unknown clip " + placement.clip + " placed in " + where); }
			checkPlacement(placement, where);
			checkWindow(placement, findClip(doc, placement.clip), clip);
		}
	}
	checkAcyclic(doc, doc.root, []);
	for (const clip of doc.clips) { checkAcyclic(doc, clip.id, []); }
}
