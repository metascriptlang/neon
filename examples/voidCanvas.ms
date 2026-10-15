// Coloured cell-grid rows inside one full-window <Void> on sokol_app's window (the browser
// canvas under --os=emcc), with the frame counts a timer's write asks for and the window draws.
//   msc build examples/voidCanvas.ms --output=out/voidCanvas.exe
//   out/voidCanvas.exe            (run from the neon checkout: the font path is relative)

import { element } from "../src/macros/ui/element";
import { NeonNode } from "../src/render/node";
import { NeonEvent } from "../src/render/event";
import { Accessor } from "../src/core/signal";
import { createList, List } from "../src/core/list";
import { ForList } from "../src/macros/ui/flow";
import { PixelRatio } from "../src/api/pixelRatio";
import { TextSpan } from "../src/render/hostTypes";
import { Void, View, Text } from "../src/components/primitives";
import { runCanvas, CanvasOptions, canvasOptions, canvasFrameCounts } from "../src/platform/sokol/canvas";
import { exit } from "std/process";

interface GridRow {
	spans: TextSpan[];
}

function span(text: string, color: string): TextSpan {
	return { text, style: { color } };
}

function lineRow(item: Accessor<GridRow>): NeonNode {
	return element(<Text style={{ fontSize: 14, color: "#cccccc", height: 18 }} cellWidth={8.4} spans={item().spans} />);
}

function counts(label: string): void {
	const c = canvasFrameCounts();
	console.log(`${label}: ticks=${c[0]} requested=${c[1]} drawn=${c[2]}`);
}

function App(): NeonNode {
	const rows: List<GridRow> = createList<GridRow>([
		{ spans: [span("red ", "#ff0000"), span("green ", "#00ff00"), span("blue", "#0000ff")] },
		{ spans: [{ text: " inverse ", style: { color: "#000000", backgroundColor: "#ffff00" } }, span(" plain", "#cccccc")] },
		{ spans: [
			{ text: "underlined", style: { color: "#88ccff", textDecorationLine: "underline" } },
			{ text: " struck", style: { color: "#ff8888", textDecorationLine: "line-through" } },
		] },
		{ spans: [span("Neon on a sokol canvas", "#cccccc")] },
	]);
	setTimeout((): void => { counts("baseline"); }, 400);
	setTimeout((): void => { rows.set(3, { spans: [span("tick 1", "#a6e3a1")] }); counts("tick 1 written"); }, 600);
	setTimeout((): void => { counts("tick 1 settled"); }, 1100);
	setTimeout((): void => { counts("idle"); }, 1500);
	setTimeout((): void => { counts("idle 1000 ms later"); }, 2500);
	return element(
		<Void style={{ backgroundColor: "#0c0c0c", padding: 6 }}>
			<View style={{ flexGrow: 1 }} focusable
				onLayout={(e: NeonEvent): void => { console.log(`layout ${e.width}x${e.height} pixelRatio=${PixelRatio.get()}`); }}>
				{ForList<GridRow>({ each: rows, children: lineRow })}
			</View>
		</Void>
	);
}

const opts: CanvasOptions = { ...canvasOptions(640, 200), font: "../void/assets/font.ttf" };
exit(runCanvas(opts, App));
