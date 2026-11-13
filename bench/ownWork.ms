import { argv } from "std/process";
import { AsyncStorage } from "../src/api/asyncStorage";
import { installStorageServices } from "../src/api/storageServices";

function payload(rows: int32): string {
	const parts: string[] = [];
	const title = "abcdefgh".repeat(16);
	for (let i: int32 = 0; i < rows; i += 1) {
		parts.push(`{"id":${i},"title":"${title}","value":${i}}`);
	}
	return '{"rows":[' + parts.join(",") + "]}";
}

function parse(text: string): JsonValue {
	const result = JSON.parseValue(text);
	if (!result.ok) { throw new Error(result.error); }
	return result.value;
}

function check(value: JsonValue, rows: int32): void {
	if (value.kind !== JsonKind.Object) { throw new Error("not an object"); }
	const at = value.keys.indexOf("rows");
	if (at < 0) { throw new Error("rows missing"); }
	const entries = value.values[at];
	if (entries.kind !== JsonKind.Array) { throw new Error("not an array"); }
	if (entries.items.length !== rows) { throw new Error("row count"); }
	const last = entries.items[rows - 1];
	if (last.kind !== JsonKind.Object) { throw new Error("not a row"); }
	const id = last.keys.indexOf("id");
	if (id < 0 || last.values[id].asInt32() !== rows - 1) {
		throw new Error("last row id");
	}
}

async function sample(
	mode: string,
	text: string,
	rows: int32,
	round: int32,
): Promise<void> {
	let stored = text;
	installStorageServices({
		storageGet: (_key: string): string | null => stored,
		storageSet: (_key: string, value: string): void => { stored = value; },
		storageRemove: (_key: string): void => {},
		storageClear: (): void => {},
		storageKeys: (): string[] => ["profile"],
	});
	let last = performance.now();
	let gap: float64 = 0.0;
	let ticks: int32 = 0;
	const heartbeat = setInterval((): void => {
		const now = performance.now();
		gap = Math.max(gap, now - last);
		last = now;
		ticks += 1;
	}, 2);
	try {
		await sleepAsync(10);
		gap = 0.0;
		ticks = 0;
		last = performance.now();
		const started = last;
		if (mode === "parse-worker-scalar") {
			const count = await spawn((): int32 => {
				const value = parse(text);
				check(value, rows);
				return rows;
			});
			if (count !== rows) { throw new Error("worker row count"); }
		} else if (mode === "parse-worker") {
			const value = await spawn((): JsonValue => parse(text));
			check(value, rows);
		} else if (mode === "parse-main") {
			const value = parse(text);
			check(value, rows);
		} else {
			if (mode !== "merge-main") { throw new Error("unknown profile mode"); }
			await AsyncStorage.mergeItem("profile", '{"updated":true}');
		}
		const elapsed = performance.now() - started;
		await sleepAsync(5);
		console.log("own-work", mode, rows, text.byteLength, round,
			elapsed, gap, ticks);
	} finally {
		clearInterval(heartbeat);
		installStorageServices(null);
	}
	if (mode === "merge-main") {
		const value = parse(stored);
		check(value, rows);
		if (value.kind !== JsonKind.Object) { throw new Error("merged root"); }
		const at = value.keys.indexOf("updated");
		if (at < 0 || !value.values[at].asBoolean()) {
			throw new Error("merged update missing");
		}
	}
}

async function run(): Promise<void> {
	for (const rows of [16, 256, 4096, 32768, 65536]) {
		const text = payload(rows);
		for (let round: int32 = 0; round < 5; round += 1) {
			const modes = round % 2 === 0
				? ["parse-main", "parse-worker", "parse-worker-scalar", "merge-main"]
				: ["merge-main", "parse-worker-scalar", "parse-worker", "parse-main"];
			for (const mode of modes) { await sample(mode, text, rows, round); }
		}
	}
}

if (argv.includes("--timer-entry")) {
	setTimeout((): void => { run(); }, 0);
} else {
	await run();
}
