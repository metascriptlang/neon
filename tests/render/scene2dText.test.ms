import { accessor, createSignal } from "../../src/core/signal";
import { flush } from "../../src/core/runtime";
import { createRoot } from "../../src/core/owner";
import { element } from "../../src/macros/ui/element";
import { Show } from "../../src/macros/ui/flow";
import { HostNode, mockNode, mockHost, render } from "../../src/render/host";
import { NeonNode } from "../../src/render/node";
import { Void } from "../../src/components/primitives";
import { Scene2D, Label } from "../../src/components/scene2d";
import { NodeRef, SelectionRange, nodeCount, Scene2D as VoidScene2D } from "../../../void/src/void2d/node";
import { rgba, Color } from "../../../void/src/void2d/types";
import { DEFAULT_FONT } from "../../../void/src/void2d/font";
import { TextRun, Truncate } from "../../../void/src/void2d/textLayout";
import { calcTextWidth } from "../../../void/src/void2d/render";
import { labelTexts, labelLines, cursorShown, advanceBlink } from "../../../void/src/void2d/labelText";

function run(len: int32): TextRun {
	return { len: len, font: DEFAULT_FONT, color: rgba(1.0, 1.0, 1.0, 1.0),
		background: rgba(0.0, 0.0, 0.0, 0.0), underline: rgba(0.0, 0.0, 0.0, 0.0),
		wavy: false, strikethrough: rgba(0.0, 0.0, 0.0, 0.0) };
}

test "Label owns run and shaping-break snapshots and binds line options reactively" {
	const nodes: NodeRef[] = [];
	const initialRuns: TextRun[] = [run(2), run(2)];
	const initialBreaks: int32[] = [2];
	const [runs, setRuns] = createSignal<TextRun[]>(initialRuns);
	const [breaks, setBreaks] = createSignal<int32[]>(initialBreaks);
	const [truncate, setTruncate] = createSignal<Truncate>(Truncate.None);
	const [indent, setIndent] = createSignal<float32>(3.0);
	const [width, setWidth] = createSignal<float32>(8.0);
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene2D>
		<Label text="abcd" size={13.0} color={rgba(1.0, 1.0, 1.0, 1.0)}
			textRuns={runs()} shapingBreaks={breaks()} truncate={truncate()}
			hangingIndent={indent()} forceWidth={width()}
			ref={(node: NodeRef): void => { nodes.push(node); }} />
	</Scene2D></Void>), mockHost(), root as unknown as HostNode);
	const node = nodes[0];
	const row = node.scene.payloads[node.id.index];
	assert labelTexts[row].runs.length === 2 && labelTexts[row].runs[0].len === 2;
	assert labelTexts[row].shapingBreaks[0] === 2;
	assert labelLines(row).truncate === Truncate.None;
	assert labelLines(row).hangingIndent === 3.0 && labelLines(row).forceWidth === 8.0;
	const measured = node.calcTextWidth("abc");
	if (!measured.ok) { throw new Error("text fixture: " + measured.error.toString()); }
	assert measured.value === 24.0;
	initialRuns[0].len = 1; initialBreaks[0] = 999;
	assert labelTexts[row].runs[0].len === 2 && labelTexts[row].shapingBreaks[0] === 2;
	setRuns([run(4)]); setBreaks([1, 3]); setTruncate(Truncate.End); setIndent(6.0); setWidth(10.0);
	flush();
	assert node.scene.payloads[node.id.index] === row;
	assert labelTexts[row].runs.length === 1 && labelTexts[row].runs[0].len === 4;
	assert labelTexts[row].shapingBreaks.length === 2 && labelTexts[row].shapingBreaks[1] === 3;
	assert labelLines(row).truncate === Truncate.End;
	assert labelLines(row).hangingIndent === 6.0 && labelLines(row).forceWidth === 10.0;
	setRuns([]); setBreaks([]); setTruncate(Truncate.None);
	flush();
	assert labelTexts[row].runs.length === 0 && labelTexts[row].shapingBreaks.length === 0;
	dispose(); setRuns([run(1)]); setWidth(4.0);
	flush();
	assert !node.isLive() && node.scene.closed;
}

test "Label remount applies current runs and line options without changing omitted siblings" {
	const nodes: NodeRef[] = [];
	const [shown, setShown] = createSignal(true);
	const [runs, setRuns] = createSignal<TextRun[]>([run(2)]);
	const [width, setWidth] = createSignal<float32>(5.0);
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene2D>
		<Label text="ab" size={13.0} color={rgba(1.0, 1.0, 1.0, 1.0)}
			ref={(node: NodeRef): void => { nodes.push(node); }} />
		{Show({ when: accessor(() => shown()), children: element(
			<Label text="ab" size={13.0} color={rgba(1.0, 1.0, 1.0, 1.0)}
				textRuns={runs()} forceWidth={width()}
				ref={(node: NodeRef): void => { nodes.push(node); }} />
		) })}
	</Scene2D></Void>), mockHost(), root as unknown as HostNode);
	const siblingRow = nodes[0].scene.payloads[nodes[0].id.index];
	assert labelTexts[siblingRow].runs.length === 0 && labelTexts[siblingRow].shapingBreaks.length === 0;
	assert labelLines(siblingRow).truncate === Truncate.None && labelLines(siblingRow).forceWidth === 0.0;
	setShown(false);
	flush();
	setRuns([run(1), run(1)]); setWidth(12.0); setShown(true);
	flush();
	assert !nodes[1].isLive();
	const row = nodes[2].scene.payloads[nodes[2].id.index];
	assert labelTexts[row].runs.length === 2 && labelLines(row).forceWidth === 12.0;
	assert labelTexts[siblingRow].runs.length === 0 && labelLines(siblingRow).forceWidth === 0.0;
	dispose(); setShown(false); setWidth(2.0);
	flush();
	assert !nodes[0].isLive() && !nodes[2].isLive() && nodes[0].scene.closed;
}

test "Label selection cursor and blink parameters react and preserve omitted defaults" {
	const nodes: NodeRef[] = [];
	const [range, setRange] = createSignal<SelectionRange>({ start: 0, length: 2 });
	const [color, setColor] = createSignal<Color>(rgba(0.1, 0.2, 0.3, 0.5));
	const [cursor, setCursor] = createSignal<int32>(1);
	const [blink, setBlink] = createSignal<float32>(0.25);
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene2D>
		<Label text="abcd" size={13.0} color={rgba(1.0, 1.0, 1.0, 1.0)}
			selectionRange={range()} selectionColor={color()} cursorIndex={cursor()}
			cursorColor={color()} cursorBlinkTime={blink()}
			ref={(node: NodeRef): void => { nodes.push(node); }} />
		<Label text="abcd" size={13.0} color={rgba(1.0, 1.0, 1.0, 1.0)}
			ref={(node: NodeRef): void => { nodes.push(node); }} />
	</Scene2D></Void>), mockHost(), root as unknown as HostNode);
	const row = nodes[0].scene.payloads[nodes[0].id.index];
	const sibling = nodes[1].scene.payloads[nodes[1].id.index];
	assert labelTexts[row].selectionStart === 0 && labelTexts[row].selectionLength === 2;
	assert labelTexts[row].selectionColor === color() && labelTexts[row].cursorColor === color();
	assert labelTexts[row].cursorIndex === 1 && labelTexts[row].cursorBlinkTime === 0.25;
	assert labelTexts[sibling].selectionLength === 0 && labelTexts[sibling].cursorIndex === -1;
	assert labelTexts[sibling].cursorBlinkTime === 0.5;
	advanceBlink(row, 0.3); assert !cursorShown(labelTexts[row]);
	setRange({ start: 1, length: 1 }); setColor(rgba(0.6, 0.7, 0.8, 0.9)); setCursor(3);
	flush();
	assert labelTexts[row].selectionStart === 1 && labelTexts[row].selectionLength === 1;
	assert labelTexts[row].selectionColor === color() && labelTexts[row].cursorColor === color();
	assert labelTexts[row].cursorIndex === 3 && labelTexts[row].blinkClock === 0.0;
	setBlink(0.0); advanceBlink(row, 10.0); assert cursorShown(labelTexts[row]);
	setRange({ start: 0, length: 0 }); setCursor(-1);
	flush();
	assert labelTexts[row].selectionLength === 0 && !cursorShown(labelTexts[row]);
	assert labelTexts[sibling].selectionLength === 0 && labelTexts[sibling].cursorIndex === -1;
	dispose(); setCursor(0); setBlink(0.5);
	flush();
	assert !nodes[0].isLive() && !nodes[1].isLive() && nodes[0].scene.closed;
}

test "Incomplete Label selection and cursor pairs fail loudly and dispose failed scenes" {
	const scenes: VoidScene2D[] = [];
	const capture = (scene: VoidScene2D): void => { scenes.push(scene); };
	const bad: NeonNode[] = [
		element(<Void><Scene2D ref={capture}>
			<Label text="a" size={13.0} color={rgba(1.0, 1.0, 1.0, 1.0)} selectionRange={{ start: 0, length: 1 }} />
		</Scene2D></Void>),
		element(<Void><Scene2D ref={capture}>
			<Label text="a" size={13.0} color={rgba(1.0, 1.0, 1.0, 1.0)} selectionColor={rgba(0.0, 0.0, 1.0, 1.0)} />
		</Scene2D></Void>),
		element(<Void><Scene2D ref={capture}>
			<Label text="a" size={13.0} color={rgba(1.0, 1.0, 1.0, 1.0)} cursorIndex={0} />
		</Scene2D></Void>),
		element(<Void><Scene2D ref={capture}>
			<Label text="a" size={13.0} color={rgba(1.0, 1.0, 1.0, 1.0)} cursorColor={rgba(0.0, 0.0, 0.0, 1.0)} />
		</Scene2D></Void>),
	];
	for (let i = 0; i < 4; i++) {
		let message = "";
		createRoot((dispose: () => void): void => {
			try { bad[i](mockHost(), mockNode("root") as unknown as HostNode, null); }
			catch (error) { message = error.toString(); }
			finally { dispose(); }
		});
		const expected = i < 2 ? "Label: provide selectionRange and selectionColor together" :
			"Label: provide cursorIndex and cursorColor together";
		assert message.includes(expected), message;
		assert scenes[i].closed && scenes[i].nodeCount() === 0;
	}
}
