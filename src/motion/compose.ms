import { MotionClip, MotionDocument, MotionPlacement, MotionSlotMapping, MotionTrack, findClip } from "./document";

export struct ComposedTrack {
	track: MotionTrack;
	slot: string;
	start: float64;
	end: float64;
	rate: float64;
	duration: float64;
}

export enum StaggerFrom {
	First,
	Last,
	Center,
	Index,
}

export struct StaggerGrid {
	columns: int32;
	rows: int32;
}

export struct StaggerOptions {
	each: float64;
	start: float64;
	from: StaggerFrom;
	index: int32;
	grid: StaggerGrid | null;
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

function placementEnd(doc: MotionDocument, placement: MotionPlacement): float64 {
	return placement.start + findClip(doc, placement.clip).duration / placement.rate;
}

function contentEnd(doc: MotionDocument, clip: MotionClip): float64 {
	let end: float64 = 0;
	for (const track of clip.tracks) {
		end = Math.max(end, track.keyframes[track.keyframes.length - 1].time);
	}
	for (const placement of clip.placements) { end = Math.max(end, placementEnd(doc, placement)); }
	return end;
}

function labelTime(clip: MotionClip, name: string): float64 | null {
	for (const label of clip.labels) {
		if (label.name === name) { return label.time; }
	}
	return null;
}

function amount(text: string, position: string): float64 {
	const value = Number(text);
	if (text.trim() === "" || !Number.isFinite(value)) { fail("cannot read position " + position); }
	return value;
}

export function resolvePosition(doc: MotionDocument, clip: MotionClip, position: string): float64 {
	if (position.endsWith("%")) { fail("percent position " + position + " is not supported"); }
	const label = labelTime(clip, position);
	if (label !== null) { return label; }
	const first = position.substring(0, 1);
	if (first === "<" || first === ">") {
		const count = clip.placements.length;
		const recent = count === 0 ? null : clip.placements[count - 1];
		const rest = position.substring(1).replace("=", "");
		const offset = rest === "" ? 0 : amount(rest, position);
		if (recent === null) { return offset; }
		return (first === "<" ? recent.start : placementEnd(doc, recent)) + offset;
	}
	const equals = position.indexOf("=");
	if (equals < 0) {
		if (position.trim() === "" || !Number.isFinite(Number(position))) {
			fail("unknown label " + position + " in clip " + clip.id);
		}
		return Number(position);
	}
	const sign = equals === 0 ? "" : position.substring(equals - 1, equals);
	if (sign !== "+" && sign !== "-") { fail("cannot read position " + position); }
	const magnitude = amount(position.substring(equals + 1), position);
	const offset = sign === "-" ? -magnitude : magnitude;
	if (equals === 1) { return contentEnd(doc, clip) + offset; }
	const name = position.substring(0, equals - 1);
	const base = labelTime(clip, name);
	if (base === null) { fail("unknown label " + name + " in clip " + clip.id); }
	return base + offset;
}

export function staggerOptions(each: float64): StaggerOptions {
	return { each, start: 0, from: StaggerFrom.First, index: 0, grid: null };
}

function originIndex(options: StaggerOptions, total: int32): float64 {
	const last = (total - 1) as float64;
	return match (options.from) {
		StaggerFrom.First => 0.0,
		StaggerFrom.Last => last,
		StaggerFrom.Center => last / 2.0,
		StaggerFrom.Index => options.index as float64,
	};
}

function staggerDistance(options: StaggerOptions, origin: float64, index: int32): float64 {
	const grid = options.grid;
	if (grid === null) { return Math.abs(origin - (index as float64)); }
	const columns = grid.columns as float64;
	const rows = grid.rows as float64;
	const centered = options.from === StaggerFrom.Center;
	const fromX = centered ? (columns - 1) / 2.0 : origin % columns;
	const fromY = centered ? (rows - 1) / 2.0 : Math.floor(origin / columns) % rows;
	const at = index as float64;
	const dx = fromX - at % columns;
	const dy = fromY - Math.floor(at / columns) % rows;
	return Math.sqrt(dx * dx + dy * dy);
}

export function stagger(
	clip: string,
	rate: float64,
	slots: MotionSlotMapping[][],
	options: StaggerOptions,
): MotionPlacement[] {
	const total = slots.length;
	if (options.from === StaggerFrom.Index && (options.index < 0 || options.index >= total)) {
		fail("stagger index " + options.index.toString() + " is outside " + total.toString() + " placements");
	}
	const grid = options.grid;
	if (grid !== null && (grid.columns < 1 || grid.rows < 1)) { fail("a stagger grid needs at least one column and row"); }
	const origin = originIndex(options, total);
	const placements: MotionPlacement[] = [];
	for (let i: int32 = 0; i < total; i += 1) {
		const distance = Math.round(staggerDistance(options, origin, i) * 100) / 100;
		placements.push({ clip, start: options.start + options.each * distance, rate, slots: slots[i] });
	}
	return placements;
}
