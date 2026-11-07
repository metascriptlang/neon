// Frame delivery: a box moves on a main-thread frame loop (what Android, Void and Pulse values run),
// and the times the frame clock hands it are summarised. 1 s warm-up, then 5 s measured.
// missed = vsyncs the loop skipped; jitter = how far a step strays from a whole number of periods.
import { createSignal } from "../../src/core/signal";
import { NeonNode } from "../../src/render/node";
import { View, Text } from "../../src/components/primitives";
import { requestFrame } from "../../src/animation/frame";

const WARMUP_MS = 1000;
const MEASURE_MS = 5000;
const TRAVEL = 240;

function percentile(sorted: number[], p: number): number {
	return sorted[Math.min(sorted.length - 1, Math.floor(sorted.length * p))];
}

function summary(times: number[]): string {
	const steps: number[] = [];
	for (let i = 1; i < times.length; i += 1) { steps.push(times[i] - times[i - 1]); }
	const sorted = steps.slice().sort((a: number, b: number): number => a - b);
	const period = percentile(sorted, 0.5);
	let missed: number = 0;
	const jitter: number[] = [];
	for (const step of steps) {
		const periods = Math.max(1, Math.round(step / period));
		missed += periods - 1;
		jitter.push(Math.abs(step - periods * period));
	}
	jitter.sort((a: number, b: number): number => a - b);
	const span = times[times.length - 1] - times[0];
	const fixed = (v: number): string => (Math.round(v * 100) / 100).toString();
	return "frames done fps " + fixed(steps.length * 1000 / span) + " period " + fixed(period) +
		" missed " + missed.toString() + " jitter p50 " + fixed(percentile(jitter, 0.5)) + " p90 " +
		fixed(percentile(jitter, 0.9)) + " max " + fixed(jitter[jitter.length - 1]) + " ms";
}

export function Frames(): NeonNode {
	const [x, setX] = createSignal<number>(0);
	const [status, setStatus] = createSignal("frames running");
	const times: number[] = [];
	let start: number = -1;
	const tick = (time: number): void => {
		if (start < 0) { start = time; }
		const elapsed = time - start;
		setX(TRAVEL * (0.5 - 0.5 * Math.cos(elapsed / 500)));
		if (elapsed >= WARMUP_MS) { times.push(time); }
		if (elapsed < WARMUP_MS + MEASURE_MS) {
			requestFrame(tick);
			return;
		}
		const report = summary(times);
		console.log(report);
		setStatus(report);
	};
	requestFrame(tick);
	return <View style={{ flex: 1, backgroundColor: "#1e1e2e", justifyContent: "center", padding: 24 }}>
		<View style={{ width: 48, height: 48, borderRadius: 8, backgroundColor: "#89b4fa", transform: "translateX(" + x().toString() + "px)" }} />
		<Text style={{ color: "#cdd6f4", fontSize: 16, marginTop: 24 }}>{status()}</Text>
	</View>;
}
