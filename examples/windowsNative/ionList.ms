// A 10000-row FlatList with getItemLayout and a SectionList with headers in a Windows Ion window: only a window of rows is
// rendered, a wheel, scrollToIndex, scrollToEnd and scrollToLocation land on the right rows (each row's colour encodes its
// index), and a section header scrolls away because sticky headers are off by default outside iOS, as in RN.
//   msc build examples/windowsNative/ionList.ms --output=out/windowsIonList.exe
//   out/windowsIonList.exe            opens the window
//   out/windowsIonList.exe --check    wheels and scrolls by itself, samples its pixels, exits 0 when all match

import { runNativeWindow, nativeWindowOptions } from "../../src/platform/windows/ion";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { NeonNode } from "../../src/render/node";
import { Style } from "../../src/render/style";
import { View } from "../../src/components/primitives";
import { FlatList, FlatListHandle, ItemLayout, ListRenderItemInfo } from "../../src/components/flatList";
import { SectionBase, SectionInfo, SectionList, SectionListHandle, SectionListRenderItemInfo } from "../../src/components/sectionList";
import { harnessIsCheck, harnessExpect, harnessSample, harnessWheel } from "./harness.h";
import { Window } from "../../../ion/src/index";
import { exit } from "std/process";

when (windows) {
	@compile("./harness.cpp");
	@passL("-ld3d11");
	@passL("-ld2d1");
	@passL("-ldcomp");
	@passL("-ldwmapi");
	@passL("-lgdi32");
}

const ROW = 50;
const COUNT = 10000;
const CELL = 40;
const PER_SECTION = 4;
const SECTIONS = 4;

const styles = createStyles({
	base: { flexGrow: 1, backgroundColor: "#101820" },
	flat: { position: "absolute", left: 20, top: 20, width: 200, height: 200, flexGrow: 0 },
	sectioned: { position: "absolute", left: 240, top: 20, width: 140, height: 200, flexGrow: 0 },
});

interface Entry {
	id: string;
	n: int32;
}

interface Group extends SectionBase<Entry> {
	s: number;
}

const HEX = "0123456789abcdef";

function hex2(v: int32): string {
	return HEX.charAt(v / 16) + HEX.charAt(v % 16);
}

function rowStyle(n: int32): Style {
	return { height: ROW, backgroundColor: "#" + hex2(n % 256) + hex2((n / 256) % 256) + "40" };
}

const HEADER_COLORS: string[] = ["#e63a3a", "#1c73d9", "#2ecc71", "#f1c40f"];
const ITEM_COLORS: string[] = ["#5a2323", "#1b3a5e", "#1d5e3a", "#5e5a1d"];

const entries: Entry[] = [];
for (let i: int32 = 0; i < COUNT; i += 1) { entries.push({ id: "e" + i.toString(), n: i }); }

const groups: Group[] = [];
for (let s = 0; s < SECTIONS; s += 1) {
	const data: Entry[] = [];
	for (let i: int32 = 0; i < PER_SECTION; i += 1) { data.push({ id: "s" + s.toString() + "i" + i.toString(), n: i }); }
	groups.push({ data, key: "g" + s.toString(), s });
}

function rowLayout(data: Entry[], index: number): ItemLayout {
	return { length: ROW, offset: ROW * index, index };
}

// Cells per section: a header, PER_SECTION items, and a footer cell that renders nothing.
function sectionLayout(data: Group[], index: number): ItemLayout {
	const cells = PER_SECTION + 2;
	const section = Math.floor(index / cells);
	const at = index % cells;
	return { length: at === cells - 1 ? 0 : CELL, offset: (section * (PER_SECTION + 1) + at) * CELL, index };
}

let rendered = 0;
let flat: FlatListHandle | null = null;
let sectioned: SectionListHandle | null = null;

function App(): NeonNode {
	return <View style={styles.base}>
		<FlatList data={entries} style={styles.flat} getItemLayout={rowLayout}
			ref={(h: FlatListHandle): void => { flat = h; }}
			renderItem={(info: ListRenderItemInfo<Entry>): NeonNode => {
				rendered += 1;
				return <View style={rowStyle(info.item.n)} />;
			}} />
		<SectionList sections={groups} style={styles.sectioned} getItemLayout={sectionLayout}
			ref={(h: SectionListHandle): void => { sectioned = h; }}
			renderSectionHeader={(info: SectionInfo<Group>): NeonNode => <View style={{ height: CELL, backgroundColor: HEADER_COLORS[info.section.s] }} />}
			renderItem={(info: SectionListRenderItemInfo<Entry, Group>): NeonNode => <View style={{ height: CELL, backgroundColor: ITEM_COLORS[info.section().s] }} />} />
	</View>;
}

const TITLE = "Neon list on Ion";
const check = harnessIsCheck() !== 0;

function expectBelow(name: string, got: number, limit: number): int32 {
	if (got < limit) { return 0; }
	console.log(`MISMATCH ${name}: got ${got}, want below ${limit}`);
	return 1;
}

function expectRow(name: string, n: int32, y: int32): void {
	harnessExpect(name, 100, y, n % 256, (n / 256) % 256, 0x40);
}

function fail(failures: int32): void {
	if (failures !== 0) { exit(failures); }
}

function atStart(): void {
	expectRow("row 0", 0, 45);
	expectRow("row 3", 3, 195);
	harnessExpect("clipped below", 100, 250, 16, 24, 32);
	harnessExpect("header 0", 300, 40, 230, 58, 58);
	harnessExpect("item of section 0", 300, 80, 90, 35, 35);
	fail(harnessSample(TITLE) + expectBelow("rows rendered at start", rendered, 300));
	harnessWheel(TITLE, 100, 100, -1000);
	setTimeout(afterWheel, 1300);
}

function afterWheel(): void {
	expectRow("row 20 after wheel", 20, 45);
	expectRow("row 23 after wheel", 23, 195);
	fail(harnessSample(TITLE));
	(flat as FlatListHandle).scrollToIndex({ index: 5000, animated: false });
	setTimeout(afterScrollToIndex, 500);
}

function afterScrollToIndex(): void {
	expectRow("row 5000 at the top", 5000, 45);
	expectRow("row 5003 at the bottom", 5003, 195);
	fail(harnessSample(TITLE));
	(flat as FlatListHandle).scrollToEnd({ animated: false });
	setTimeout(afterScrollToEnd, 500);
}

function afterScrollToEnd(): void {
	expectRow("row 9996 at the top", 9996, 45);
	expectRow("row 9999 at the bottom", 9999, 195);
	fail(harnessSample(TITLE) + expectBelow("rows rendered in total", rendered, 1000));
	(sectioned as SectionListHandle).scrollToLocation({ sectionIndex: 2, itemIndex: 0, animated: false });
	setTimeout(afterScrollToLocation, 500);
}

function afterScrollToLocation(): void {
	harnessExpect("header 2 at the top", 300, 40, 46, 204, 113);
	harnessExpect("item of section 2 below it", 300, 80, 29, 94, 58);
	fail(harnessSample(TITLE));
	harnessWheel(TITLE, 300, 100, -50);
	setTimeout(afterSectionWheel, 1300);
}

function afterSectionWheel(): void {
	harnessExpect("header 2 scrolled away", 300, 25, 29, 94, 58);
	harnessExpect("flat list unmoved", 100, 195, 0x0f, 0x27, 0x40);
	exit(harnessSample(TITLE));
}

const options = nativeWindowOptions(TITLE, 400, 300);
options.topmost = check;
exit(runNativeWindow(options, App, check ? (win: Window): void => { setTimeout(atStart, 700); } : null));
