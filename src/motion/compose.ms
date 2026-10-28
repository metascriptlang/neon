import { MotionClip, MotionDocument, MotionSlotMapping, MotionTrack, findClip } from "./document";

export struct ComposedTrack {
	track: MotionTrack;
	slot: string;
	start: float64;
	end: float64;
	rate: float64;
	duration: float64;
}

function fail(message: string): never {
	throw new Error("motion: " + message);
}

function roundPrecise(value: float64): float64 {
	return Math.round(value * 1e8) / 1e8;
}

function mapSlot(slot: string, mappings: MotionSlotMapping[]): string {
	for (const mapping of mappings) {
		if (mapping.from === slot) { return mapping.to; }
	}
	return slot;
}

function flattenClip(
	doc: MotionDocument,
	clip: MotionClip,
	offset: float64,
	rate: float64,
	mappings: MotionSlotMapping[][],
	out: ComposedTrack[],
): void {
	const end = roundPrecise(offset + clip.duration / rate);
	for (const track of clip.tracks) {
		let slot = track.slot;
		for (let i: int32 = mappings.length - 1; i >= 0; i -= 1) { slot = mapSlot(slot, mappings[i]); }
		out.push({ track, slot, start: offset, end, rate, duration: clip.duration });
	}
	for (const placement of clip.placements) {
		mappings.push(placement.slots);
		const start = roundPrecise(offset + placement.start / rate);
		flattenClip(doc, findClip(doc, placement.clip), start, rate * placement.rate, mappings, out);
		mappings.pop();
	}
}

export function flatten(doc: MotionDocument): ComposedTrack[] {
	const out: ComposedTrack[] = [];
	flattenClip(doc, findClip(doc, doc.root), 0, 1, [], out);
	return out;
}

export function localTime(this writer: ComposedTrack, time: float64): float64 {
	return Math.min(Math.max((time - writer.start) * writer.rate, 0), writer.duration);
}

export function writerAt(writers: ComposedTrack[], reached: boolean[], time: float64): int32 {
	let covering: int32 = -1;
	let ended: int32 = -1;
	let ahead: int32 = -1;
	for (let i: int32 = 0; i < writers.length; i += 1) {
		const writer = writers[i];
		if (writer.start <= time && time <= writer.end) {
			if (covering < 0 || writer.start >= writers[covering].start) { covering = i; }
		} else if (writer.end < time) {
			const best = ended < 0 ? null : writers[ended];
			if (best === null || writer.end > best.end || (writer.end === best.end && writer.start >= best.start)) {
				ended = i;
			}
		} else if (reached[i] && (ahead < 0 || writer.start < writers[ahead].start)) {
			ahead = i;
		}
	}
	if (covering >= 0) { return covering; }
	return ended >= 0 ? ended : ahead;
}
