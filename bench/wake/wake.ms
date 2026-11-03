// Result latency: how long a finished worker's result waits before the main thread sees it.
// Each job sleeps on a timer so the loop goes idle, runs ~100 ms of work on a worker that stamps
// when it finished, and the main thread records now minus that stamp. A 1 s heartbeat stands for
// the timers a real app has, so a loop that is never woken still sees each result at the next beat.
import { createSignal } from "../../src/core/signal";
import { NeonNode } from "../../src/render/node";
import { View, Text } from "../../src/components/primitives";

const JOBS = 20;
const IDLE_MS = 300;
const HEARTBEAT_MS = 1000;

function fib(n: int32): int32 { return n < 2 ? n : fib(n - 1) + fib(n - 2); }

function work(): number {
	fib(30);
	return performance.now();
}

function sleep(ms: number): Promise<void> {
	return new Promise<void>((resolve: () => void): void => { setTimeout(resolve, ms); });
}

async function job(): Promise<number> {
	await sleep(IDLE_MS);
	const finished = await spawn(work);
	return performance.now() - finished;
}

function percentile(sorted: number[], p: number): number {
	return sorted[Math.min(sorted.length - 1, Math.floor(sorted.length * p))];
}

export function Wake(): NeonNode {
	const [status, setStatus] = createSignal("wake 0/" + JOBS.toString());
	setInterval((): void => {}, HEARTBEAT_MS);
	const run = async (): Promise<void> => {
		const lags: number[] = [];
		for (let i = 0; i < JOBS; i += 1) {
			lags.push(await job());
			setStatus("wake " + (i + 1).toString() + "/" + JOBS.toString());
		}
		const sorted = lags.slice().sort((a: number, b: number): number => a - b);
		const report = "wake done p50 " + Math.round(percentile(sorted, 0.5)).toString() + " p90 " +
			Math.round(percentile(sorted, 0.9)).toString() + " max " + Math.round(sorted[sorted.length - 1]).toString() +
			" ms | " + lags.map((v: number): string => Math.round(v).toString()).join(",");
		console.log(report);
		setStatus(report);
	};
	run();
	return <View style={{ flex: 1, backgroundColor: "#1e1e2e", justifyContent: "center", padding: 24 }}>
		<Text style={{ color: "#cdd6f4", fontSize: 18 }}>{status()}</Text>
	</View>;
}
