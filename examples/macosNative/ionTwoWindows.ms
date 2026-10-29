import { runNativeWindow, nativeWindowOptions, mountNativeWindow } from "../../src/platform/macos/ion";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { NeonNode } from "../../src/render/node";
import { NeonEvent } from "../../src/render/event";
import { View, TextInput } from "../../src/components/primitives";
import { onCleanup } from "../../src/core/cleanup";
import { requestFrame } from "../../src/animation/frame";
import { Accessor } from "../../src/core/signal";
import { WindowDimensions, useWindowDimensions } from "../../src/render/environment";
import { harnessIsCheck, harnessExpect, harnessSample, harnessClick, harnessPostKeys, harnessFocusedText } from "./harness.h";
import { createWindow, defaultOptions, closeWindow, show, hide, focus, setSize, Window } from "../../../ion/src/index";
import { exit } from "std/process";

when (macos) {
	@compile("./harness.m", "-fobjc-arc");
}

const MAIN = "Neon board";
const PANEL = "Neon launcher";

const styles = createStyles({
	board: { flex: 1, backgroundColor: "#101820" },
	column: { position: "absolute", left: 20, top: 80, width: 140, height: 200, backgroundColor: "#2e86de" },
	mainField: { position: "absolute", left: 20, top: 20, width: 300, backgroundColor: "#ffffff", color: "#101820", fontSize: 20, padding: 6 },
	panel: { flex: 1, backgroundColor: "#c0392b" },
	panelField: { position: "absolute", left: 20, top: 16, width: 300, backgroundColor: "#ffffff", color: "#101820", fontSize: 20, padding: 6 },
});

let mainValue = "";
let mainChanges = 0;
let mainFocuses = 0;
let mainBlurs = 0;
let boardWidth: number = 0;
let boardLayouts = 0;
let panelValue = "";
let panelFocuses = 0;
let panelLayouts = 0;
let panelDisposed = false;
let boardSize: Accessor<WindowDimensions> | null = null;
let panelSize: Accessor<WindowDimensions> | null = null;

function Board(): NeonNode {
	boardSize = useWindowDimensions();
	return <View style={styles.board} onLayout={(e: NeonEvent): void => {
		boardWidth = e.width;
		boardLayouts += 1;
	}}>
		<View style={styles.column} />
		<TextInput style={styles.mainField} onChangeText={(t: string): void => {
			mainValue = t;
			mainChanges += 1;
		}} onFocus={(e: NeonEvent): void => { mainFocuses += 1; }} onBlur={(e: NeonEvent): void => { mainBlurs += 1; }} />
	</View>;
}

function Launcher(): NeonNode {
	onCleanup((): void => { panelDisposed = true; });
	panelSize = useWindowDimensions();
	return <View style={styles.panel} onLayout={(e: NeonEvent): void => { panelLayouts += 1; }}>
		<TextInput style={styles.panelField} onChangeText={(t: string): void => { panelValue = t; }}
			onFocus={(e: NeonEvent): void => { panelFocuses += 1; }} />
	</View>;
}

const check = harnessIsCheck() !== 0;
let failures = 0;
let mainWindow: Window | null = null;
let panelWindow: Window | null = null;
let frames = 0;
let counting = false;

function expect(what: string, ok: boolean, detail: string): void {
	console.log(`${ok ? "PASS" : "FAIL"} ${what}: ${detail}`);
	if (!ok) { failures += 1; }
}

function countFrame(time: number): void {
	if (!counting) { return; }
	frames += 1;
	requestFrame(countFrame);
}

function main(): Window { return mainWindow as Window; }
function panel(): Window { return panelWindow as Window; }

const steps: (() => void)[] = [];

function run(at: number): void {
	if (at >= steps.length) {
		console.log(failures === 0 ? "ionTwoWindows: all PASS" : `ionTwoWindows: ${failures} FAIL`);
		exit(failures);
		return;
	}
	steps[at]();
	setTimeout((): void => { run(at + 1); }, 600);
}

steps.push((): void => {
	harnessClick(MAIN, 300, 35);
	harnessPostKeys(MAIN, "m");
});
steps.push((): void => {
	expect("typing reaches the main field", mainValue === "m" && mainFocuses === 1, `"${mainValue}", focuses ${mainFocuses}`);
	const options = defaultOptions(PANEL, 340 as int32, 72 as int32);
	options.panel = true;
	options.alwaysOnTop = true;
	options.resizable = false;
	const created = createWindow("launcher", options);
	if (created === null) {
		expect("the panel window opens", false, "createWindow returned null");
		return;
	}
	panelWindow = created;
	mountNativeWindow(panel(), Launcher);
	show(panel());
	focus(panel());
});
steps.push((): void => {
	expect("the panel mounts its own root", panelLayouts > 0, `${panelLayouts} layouts`);
	const side = (panelSize as Accessor<WindowDimensions>)();
	const board = (boardSize as Accessor<WindowDimensions>)();
	expect("each window's useWindowDimensions answers its own size", side.width === 340 && side.height === 72 && board.width === boardWidth, `panel ${side.width}x${side.height}, board ${board.width}x${board.height}, board layout width ${boardWidth}`);
	harnessExpect("panel background", 330, 64, 192, 57, 43);
	harnessExpect("panel field", 30, 26, 255, 255, 255);
	failures += harnessSample(PANEL);
	harnessClick(PANEL, 300, 30);
	harnessPostKeys(PANEL, "abc");
});
steps.push((): void => {
	expect("typing reaches the panel field", panelValue === "abc" && panelFocuses === 1, `"${panelValue}", focuses ${panelFocuses}`);
	expect("the main field's value is unchanged", mainValue === "m" && mainChanges === 1, `"${mainValue}" after ${mainChanges} changes`);
	expect("the main field keeps its focus", mainBlurs === 0 && harnessFocusedText(MAIN) === 1, `blurs ${mainBlurs}, focused text ${harnessFocusedText(MAIN)}`);
	hide(panel());
});
steps.push((): void => {
	expect("hiding the panel keeps its root", !panelDisposed, `disposed ${panelDisposed}`);
	boardLayouts = 0;
	setSize(main(), 600 as int32, 360 as int32);
});
steps.push((): void => {
	expect("the board lays out after a resize with the panel hidden", boardLayouts > 0 && boardWidth === 600, `${boardLayouts} layouts, width ${boardWidth}`);
	harnessExpect("board repainted at its new edge", 590, 350, 16, 24, 32);
	failures += harnessSample(MAIN);
	frames = 0;
	counting = true;
	requestFrame(countFrame);
});
steps.push((): void => {
	counting = false;
	expect("frames reach the board", frames > 10, `${frames} frames in 0.6 s`);
	show(panel());
	hide(main());
	frames = 0;
	counting = true;
	requestFrame(countFrame);
});
steps.push((): void => {
	counting = false;
	expect("frames reach the panel while the main window is hidden", frames > 10, `${frames} frames in 0.6 s`);
	show(main());
	closeWindow(panel());
});
steps.push((): void => {
	expect("closing the panel disposes its root", panelDisposed, `disposed ${panelDisposed}`);
	boardLayouts = 0;
	setSize(main(), 520 as int32, 340 as int32);
	focus(main());
});
steps.push((): void => {
	expect("the board lays out after the panel closed", boardLayouts > 0 && boardWidth === 520, `${boardLayouts} layouts, width ${boardWidth}`);
	harnessExpect("board repainted after the panel closed", 510, 330, 16, 24, 32);
	harnessExpect("board column", 30, 90, 46, 134, 222);
	failures += harnessSample(MAIN);
	harnessClick(MAIN, 300, 35);
	harnessPostKeys(MAIN, "n");
});
steps.push((): void => {
	expect("the main field still takes typing", mainValue === "mn", `"${mainValue}"`);
});

const options = nativeWindowOptions(MAIN, 480, 320);
options.topmost = check;
exit(runNativeWindow(options, Board, check ? (win: Window): void => {
	mainWindow = win;
	setTimeout((): void => { run(0); }, 700);
} : null));
