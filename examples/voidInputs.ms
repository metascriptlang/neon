// A focusable grid of ForList rows inside one full-window <Void>: it logs the key, pointer,
// wheel, text and preedit events a terminal grid needs, the scale PixelRatio reports, and
// how many frames a timer's signal write asks for and the window draws.
//   msc build examples/voidInputs.ms --output=out/voidInputs.exe
//   out/voidInputs.exe            (run from the neon checkout: the font path is relative)

import { element } from "../src/macros/ui/element";
import { NeonNode } from "../src/render/node";
import { NeonEvent } from "../src/render/event";
import { Accessor } from "../src/core/signal";
import { createList, List } from "../src/core/list";
import { ForList } from "../src/macros/ui/flow";
import { PixelRatio } from "../src/api/pixelRatio";
import { Void, View, Text } from "../src/components/primitives";
import { runWindow, DesktopOptions, desktopOptions, frameCounts } from "../src/platform/ion/window";
import { exit } from "std/process";

interface Line {
	text: string;
}

function lineRow(item: Accessor<Line>): NeonNode {
	return element(<Text style={{ fontSize: 16, color: "#cdd6f4" }}>{item().text}</Text>);
}

function counts(label: string): void {
	const c = frameCounts();
	console.log(`${label}: requested=${c[0]} drawn=${c[1]}`);
}

function describe(e: NeonEvent): string {
	return `${e.type} button=${e.button} pressed=${e.pressed} at ${e.x},${e.y} local ${e.locationX},${e.locationY} wheel ${e.deltaX},${e.deltaY}`;
}

function App(): NeonNode {
	const lines: Line[] = [];
	for (let i = 0; i < 6; i += 1) { lines.push({ text: `row ${i}` }); }
	const rows: List<Line> = createList<Line>(lines);
	setTimeout((): void => { counts("baseline"); }, 400);
	setTimeout((): void => { rows.set(0, { text: "tick 1" }); counts("tick 1 written"); }, 600);
	setTimeout((): void => { counts("tick 1 settled"); }, 1100);
	setTimeout((): void => { rows.set(1, { text: "tick 2" }); rows.set(2, { text: "tick 2" }); counts("tick 2 written, two rows"); }, 1400);
	setTimeout((): void => { counts("tick 2 settled"); }, 1900);
	setTimeout((): void => { counts("idle"); }, 2300);
	setTimeout((): void => { counts("idle 650 ms later"); }, 2950);
	return element(
		<Void style={{ backgroundColor: "#1e1e2e" }}>
			<View style={{ flexGrow: 1 }} focusable imeRect={{ x: 0, y: 0, width: 8, height: 16 }}
				onLayout={(e: NeonEvent): void => { console.log(`layout ${e.width}x${e.height} pixelRatio=${PixelRatio.get()} device ${PixelRatio.getPixelSizeForLayoutSize(e.width)}x${PixelRatio.getPixelSizeForLayoutSize(e.height)}`); }}
				onKeyDown={(e: NeonEvent): void => { console.log(`keydown key=${e.key} code=${e.code} scancode=${e.scancode} mods=${e.mods} consumed=${e.consumedMods} unshifted=${e.unshifted} text="${e.text}" repeat=${e.repeat}`); }}
				onKeyUp={(e: NeonEvent): void => { console.log(`keyup code=${e.code} scancode=${e.scancode}`); }}
				onTextInput={(e: NeonEvent): void => { console.log(`textinput "${e.text}"`); }}
				onPreedit={(e: NeonEvent): void => { console.log(`preedit "${e.text}" cursor=${e.cursor}`); }}
				onPointerDown={(e: NeonEvent): void => { console.log(describe(e)); }}
				onPointerMove={(e: NeonEvent): void => { console.log(describe(e)); }}
				onPointerUp={(e: NeonEvent): void => { console.log(describe(e)); }}
				onWheel={(e: NeonEvent): void => { console.log(describe(e)); }}
				onFocus={(): void => { console.log("focus"); }}>
				{ForList<Line>({ each: rows, children: lineRow })}
			</View>
		</Void>
	);
}

const opts: DesktopOptions = { ...desktopOptions("Neon void inputs", 640, 360), font: "../void/assets/font.ttf" };
exit(runWindow(opts, App));
