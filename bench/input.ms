// Pointer input per frame on the window host: k moves arrive between two frames, a move handler writes
// a signal that ROWS texts read, and the frame lays out. Prints main-thread ms per frame (median, p90)
// and how many times the handler ran, for k = 1, 2, 4, 8. Run from the Neon checkout root beside ../void.
import { createSignal } from "../src/core/signal";
import { NeonNode } from "../src/render/node";
import { render } from "../src/render/host";
import { For } from "../src/macros/ui/flow";
import { Void, View, Text } from "../src/components/primitives";
import { NeonEvent } from "../src/render/event";
import { AreaPointerKind } from "../src/render/voidAreaHandle";
import { AreaWindow, WindowArea, windowHost, windowNode, deliverPointer, deliverResize } from "../src/platform/void/windowHost";
import { useManualFrames, setFrameDriver } from "../src/animation/frame";
import { FontId, addFont } from "../../void/src/void2d/font";

const FONT_PATH = "../void/assets/font.ttf";
const ROWS = 200;
const FRAMES = 2000;

function percentile(sorted: number[], p: number): number {
	return sorted[Math.min(sorted.length - 1, Math.floor(sorted.length * p))];
}

function font(): FontId {
	const r = addFont(FONT_PATH);
	if (!r.ok) { throw new Error("the bench font did not load from " + FONT_PATH + "; run from the Neon checkout root beside ../void"); }
	return r.value;
}

function openArea(face: FontId, moved: () => void): WindowArea {
	const areas: WindowArea[] = [];
	const window: AreaWindow = {
		name: "bench window",
		font: face,
		family: null,
		pixelWidth: (): int32 => 800 as int32,
		pixelHeight: (): int32 => 600 as int32,
		requestFrame: (): void => {},
		dirty: (): void => {},
		setImeRect: (pixelX: int32, pixelY: int32, pixelW: int32, pixelH: int32): void => {},
		opened: (area: WindowArea): void => { areas.push(area); },
		released: (area: WindowArea): void => {},
	};
	const [x, setX] = createSignal(0.0);
	const rows: number[] = [];
	for (let i = 0; i < ROWS; i += 1) { rows.push(i as number); }
	render((
		<Void>
			<View style={{ width: 800, height: 600 }} onPointerMove={(e: NeonEvent): void => { moved(); setX(e.x); }}>
				<For each={rows}>{(row: number): NeonNode => <Text>{`row ${row} at ${x()}`}</Text>}</For>
			</View>
		</Void>
	), windowHost(window), windowNode("window"));
	const area = areas[0];
	deliverResize(area, 800 as int32, 600 as int32, 1.0);
	area.vh.layout(area.logicalWidth(), area.logicalHeight());
	return area;
}

function run(face: FontId, k: int32): string {
	let handled: int32 = 0;
	const area = openArea(face, (): void => { handled += 1; });
	const frames = useManualFrames();
	const costs: number[] = [];
	let px = 1.0;
	for (let f = 0; f < FRAMES; f += 1) {
		const t0 = performance.now();
		for (let i = 0; i < k; i += 1) {
			px = px >= 700.0 ? 1.0 : px + 1.0;
			deliverPointer(area, { kind: AreaPointerKind.Motion, pixelX: px, pixelY: 300.0, button: 0 as int32, pressed: false, dx: 0.0, dy: 0.0 });
		}
		frames.step(1 as int32);
		area.vh.layout(area.logicalWidth(), area.logicalHeight());
		costs.push(performance.now() - t0);
	}
	setFrameDriver(null);
	costs.sort((a: number, b: number): number => a - b);
	const fixed = (v: number): string => (Math.round(v * 1000) / 1000).toString();
	return "input k=" + k.toString() + " ms/frame p50 " + fixed(percentile(costs, 0.5)) + " p90 " + fixed(percentile(costs, 0.9)) +
		" handler runs/frame " + fixed((handled as number) / (FRAMES as number));
}

function main(): void {
	const face = font();
	for (const k of [1 as int32, 2 as int32, 4 as int32, 8 as int32]) { console.log(run(face, k)); }
}

main();
