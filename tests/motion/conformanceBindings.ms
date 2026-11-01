import {
	ConformanceResult,
	ConformanceScrollGeometry,
	ConformanceSupport,
	ConformanceTimeline,
} from "pulse/src/conformance";
import {
	ScrollAxis,
	ScrollSource,
	TimeSource,
	TimeSourceKind,
	ViewSubject,
	scrollSource,
	timeSource,
	viewSource,
} from "pulse/src/scroll";
import { MotionClip, MotionDocument, MotionTrack } from "pulse/src/document";

// Each conformance property ("box.x") becomes its own element slot on translateX: every Neon host
// carries it, and unlike opacity no host clamps it to the golden's range.
export const CHANNEL: string = "translateX";

function boundTrack(track: MotionTrack): MotionTrack {
	return { ...track, slot: track.slot + "." + track.property, property: CHANNEL };
}

export function boundDocument(doc: MotionDocument): MotionDocument {
	return {
		...doc,
		clips: doc.clips.map((clip: MotionClip): MotionClip => {
			if (clip.placements.length > 0) {
				throw new Error("conformance bindings: clip " + clip.id + " places clips; map their slots first");
			}
			return { ...clip, tracks: clip.tracks.map(boundTrack) };
		}),
	};
}

export function translateOf(transform: string): float64 {
	const at = transform.indexOf("translateX(");
	if (at < 0) { throw new Error("conformance bindings: no translateX in " + transform); }
	const start = at + "translateX(".length;
	return parseFloat(transform.substring(start, transform.indexOf("px", start)));
}

export function supportName(support: ConformanceSupport): string {
	return match (support) {
		ConformanceSupport.Engine => "Engine",
		ConformanceSupport.Evaluator => "Evaluator",
		ConformanceSupport.Refused => "Refused",
	};
}

export function conformanceReport(adapter: string, results: ConformanceResult[]): string[] {
	const failures: string[] = [];
	let passed: int32 = 0;
	let engine: int32 = 0;
	let evaluator: int32 = 0;
	let refused: int32 = 0;
	for (const result of results) {
		if (result.failures.length === 0) { passed += 1; }
		match (result.support) {
			ConformanceSupport.Engine => { engine += 1; },
			ConformanceSupport.Evaluator => { evaluator += 1; },
			ConformanceSupport.Refused => { refused += 1; },
		};
		for (const failure of result.failures) {
			failures.push("[" + supportName(result.support) + "] " + failure);
		}
	}
	console.log(
		adapter + " conformance: " + passed.toString() + "/" + results.length.toString() +
			" passed; Engine " + engine.toString() + ", Evaluator " + evaluator.toString() +
			", Refused " + refused.toString(),
	);
	return failures;
}

export class ConformanceScroller {
	geometry: ConformanceScrollGeometry = { viewport: 0, max: 0, subjectStart: 0, subjectSize: 0 };
	offset: float64 = 0;

	place(geometry: ConformanceScrollGeometry): void {
		this.geometry = geometry;
		this.scrollTo(this.offset);
	}

	scrollTo(offset: float64): void {
		this.offset = Math.min(Math.max(offset, 0), this.geometry.max);
	}

	source(timeline: ConformanceTimeline | null): TimeSource {
		if (timeline === null) { return timeSource(); }
		const scroller: ScrollSource = {
			offset: (axis: ScrollAxis): float64 => this.offset,
			max: (axis: ScrollAxis): float64 => this.geometry.max,
			viewport: (axis: ScrollAxis): float64 => this.geometry.viewport,
		};
		const subject: ViewSubject = {
			start: (axis: ScrollAxis): float64 => this.geometry.subjectStart,
			size: (axis: ScrollAxis): float64 => this.geometry.subjectSize,
		};
		return match (timeline.kind) {
			TimeSourceKind.Time => timeSource(),
			TimeSourceKind.Scroll => scrollSource(scroller, timeline.axis),
			TimeSourceKind.View => viewSource(scroller, subject, timeline.range, timeline.inset, timeline.axis),
		};
	}
}
