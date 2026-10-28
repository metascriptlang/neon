import {
	MotionDocument,
	MotionClip,
	MotionTrack,
	MotionKeyframe,
	MotionPlacement,
	ValueKind,
	numberValue,
	colorValue,
	linearKeyframe,
	validate,
} from "../../src/motion/document";

function track(slot: string, property: string, keyframes: MotionKeyframe[]): MotionTrack {
	return { slot, property, kind: ValueKind.Number, keyframes };
}

function clip(id: string, tracks: MotionTrack[], placements: MotionPlacement[]): MotionClip {
	return { id, duration: 1000, tracks, placements, labels: [] };
}

function document(clips: MotionClip[]): MotionDocument {
	return { version: 1, root: clips[0].id, clips };
}

function place(child: string): MotionPlacement {
	return { clip: child, start: 0, rate: 1, slots: [] };
}

function valid(): MotionDocument {
	return document([
		clip("main", [track("box", "x", [linearKeyframe("a", 0, 0), linearKeyframe("b", 500, 10)])], [place("leaf")]),
		clip("leaf", [track("dot", "y", [linearKeyframe("a", 0, 1)])], []),
	]);
}

function refusal(doc: MotionDocument): string {
	try { validate(doc); } catch (e) { return e.message; }
	return "";
}

function refuses(doc: MotionDocument, part: string): boolean {
	const message = refusal(doc);
	return message.startsWith("motion: ") && message.includes(part);
}

test "a well-formed document validates" {
	assert refusal(valid()) === "";
}

test "an unsupported version is refused" {
	let doc = valid();
	doc.version = 2;
	assert refuses(doc, "unsupported version");
}

test "an unknown root clip is refused" {
	let doc = valid();
	doc.root = "nope";
	assert refuses(doc, "unknown root clip");
}

test "an unknown child clip is refused" {
	let doc = valid();
	doc.clips[0].placements[0].clip = "nope";
	assert refuses(doc, "unknown clip");
}

test "a duplicate clip id is refused" {
	let doc = valid();
	doc.clips[1].id = "main";
	assert refuses(doc, "duplicate clip id");
}

test "a placement cycle is refused" {
	let doc = valid();
	doc.clips[1].placements.push(place("main"));
	assert refuses(doc, "placement cycle");
}

test "a clip placing itself is a cycle" {
	let doc = valid();
	doc.clips[1].placements.push(place("leaf"));
	assert refuses(doc, "placement cycle");
}

test "a diamond of placements is not a cycle" {
	let doc = valid();
	doc.clips[0].placements.push(place("leaf"));
	assert refusal(doc) === "";
}

test "unsorted keyframes are refused" {
	let doc = valid();
	doc.clips[0].tracks[0].keyframes = [linearKeyframe("a", 500, 0), linearKeyframe("b", 0, 10)];
	assert refuses(doc, "not sorted");
}

test "keyframes at one time are refused" {
	let doc = valid();
	doc.clips[0].tracks[0].keyframes = [linearKeyframe("a", 500, 0), linearKeyframe("b", 500, 10)];
	assert refuses(doc, "duplicate keyframe time");
}

test "a duplicate keyframe id is refused" {
	let doc = valid();
	doc.clips[0].tracks[0].keyframes = [linearKeyframe("a", 0, 0), linearKeyframe("a", 500, 10)];
	assert refuses(doc, "duplicate keyframe id");
}

test "a track without keyframes is refused" {
	let doc = valid();
	doc.clips[0].tracks[0].keyframes = [];
	assert refuses(doc, "no keyframes");
}

test "a non-finite time is refused" {
	let doc = valid();
	doc.clips[0].tracks[0].keyframes[1].time = Infinity;
	assert refuses(doc, "non-finite keyframe time");
	doc.clips[0].tracks[0].keyframes[1].time = NaN;
	assert refuses(doc, "non-finite keyframe time");
}

test "a non-finite value is refused" {
	let doc = valid();
	doc.clips[0].tracks[0].keyframes[1].value = numberValue(NaN);
	assert refuses(doc, "non-finite keyframe value");
}

test "a non-finite or non-positive duration is refused" {
	let doc = valid();
	doc.clips[0].duration = Infinity;
	assert refuses(doc, "duration");
	doc.clips[0].duration = 0;
	assert refuses(doc, "duration");
}

test "a non-finite handle is refused" {
	let doc = valid();
	doc.clips[0].tracks[0].keyframes[0].handles.rightY = NaN;
	assert refuses(doc, "non-finite handle");
}

test "a handle x outside [0, 1] is refused" {
	let doc = valid();
	doc.clips[0].tracks[0].keyframes[0].handles.rightX = 1.5;
	assert refuses(doc, "handle x must be in [0, 1]");
	doc.clips[0].tracks[0].keyframes[0].handles.rightX = 0.5;
	doc.clips[0].tracks[0].keyframes[1].handles.leftX = -0.1;
	assert refuses(doc, "handle x must be in [0, 1]");
}

test "a handle y outside [0, 1] is allowed" {
	let doc = valid();
	doc.clips[0].tracks[0].keyframes[0].handles.rightY = 2;
	doc.clips[0].tracks[0].keyframes[1].handles.leftY = -1;
	assert refusal(doc) === "";
}

test "a value kind that differs from its track is refused" {
	let doc = valid();
	doc.clips[0].tracks[0].keyframes[1].value = colorValue(0, 0, 0, 1);
	assert refuses(doc, "value kind mismatch");
}

test "a colour component outside [0, 1] is refused" {
	let doc = valid();
	doc.clips[0].tracks[0] = {
		slot: "box",
		property: "fill",
		kind: ValueKind.Color,
		keyframes: [{ ...linearKeyframe("a", 0, 0), value: colorValue(0, 2, 0, 1) }],
	};
	assert refuses(doc, "colour component");
}

test "two tracks for one slot and property in a clip are refused" {
	let doc = valid();
	doc.clips[0].tracks.push(track("box", "x", [linearKeyframe("c", 0, 1)]));
	assert refuses(doc, "duplicate track");
}

test "one property on two slots, or one slot with two properties, is allowed" {
	let doc = valid();
	doc.clips[0].tracks.push(track("box", "y", [linearKeyframe("c", 0, 1)]));
	doc.clips[0].tracks.push(track("other", "x", [linearKeyframe("c", 0, 1)]));
	assert refusal(doc) === "";
}

test "a bad placement rate or start is refused" {
	let doc = valid();
	doc.clips[0].placements[0].rate = 0;
	assert refuses(doc, "placement rate");
	doc.clips[0].placements[0].rate = 1;
	doc.clips[0].placements[0].start = NaN;
	assert refuses(doc, "placement start");
}

test "a slot mapping with an empty or repeated name is refused" {
	let doc = valid();
	doc.clips[0].placements[0].slots = [{ from: "dot", to: "" }];
	assert refuses(doc, "slot mapping");
	doc.clips[0].placements[0].slots = [{ from: "dot", to: "a" }, { from: "dot", to: "b" }];
	assert refuses(doc, "slot mapping");
}

test "a document round-trips through JSON" {
	let doc = valid();
	doc.clips[0].placements[0].slots = [{ from: "dot", to: "other" }];
	doc.clips[0].tracks.push({
		slot: "box",
		property: "fill",
		kind: ValueKind.Color,
		keyframes: [{ ...linearKeyframe("c", 0, 0), value: colorValue(0.25, 0.5, 0.75, 1), connectedRight: false }],
	});
	const text = JSON.stringify(doc);
	const parsed = JSON.parse<MotionDocument>(text);
	assert parsed.ok, "parse";
	assert JSON.stringify(parsed.value) === text;
	assert refusal(parsed.value) === "";
}
