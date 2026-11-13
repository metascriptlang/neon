import { createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { flush, resetErrorHalt } from "../../src/core/runtime";
import { createRoot } from "../../src/core/owner";
import { Show } from "../../src/macros/ui/flow";
import { render, HostNode } from "../../src/render/host";
import { NeonNode, Host } from "../../src/render/hostTypes";
import { NeonEvent } from "../../src/render/event";
import { Void, View, Text, Pressable, TextInput } from "../../src/components/primitives";
import { VoidNode } from "../../src/platform/void/host";
import { AreaWindow, WindowArea, windowHost, windowNode, deliverPointer, deliverResize, drainInput, logicalWidth, logicalHeight } from "../../src/platform/void/windowHost";
import { AreaPointerKind, AreaPointerEvent, LayerAnchor } from "../../src/render/voidAreaHandle";
import { FontId, addFont } from "../../../void/src/void2d/font";
import {
	DevScope, DevRef, DevRefusal, DevScopeError, DevActRefusal, ScopeNode, ScopeTree,
	openDevScope, closeScope, scopeTree, scopePress, scopeType,
} from "../../src/devtools/scope";

function loadedFont(): FontId {
	const r = addFont("../void/assets/font.ttf");
	if (!r.ok) { throw new Error("the test font did not load from ../void/assets/font.ttf"); }
	return r.value;
}

function testWindow(areas: WindowArea[]): AreaWindow {
	return {
		name: "dev scope window",
		font: loadedFont(),
		pixelWidth: (): int32 => 640 as int32,
		pixelHeight: (): int32 => 360 as int32,
		requestFrame: (): void => {},
		dirty: (): void => {},
		setImeRect: (pixelX: int32, pixelY: int32, pixelW: int32, pixelH: int32): void => {},
		opened: (area: WindowArea): void => { areas.push(area); },
		released: (area: WindowArea): void => {},
	};
}

class Fixture {
	area: WindowArea;
	editor: DevScope;
	app: DevScope;
	dispose: () => void;

	constructor(area: WindowArea, editor: DevScope, app: DevScope, dispose: () => void) {
		this.area = area;
		this.editor = editor;
		this.app = app;
		this.dispose = dispose;
	}
}

const [overlay, setOverlay] = createSignal(false);
const [appShown, setAppShown] = createSignal(true);
const [throwOnPress, setThrowOnPress] = createSignal(false);
const [throwOnDown, setThrowOnDown] = createSignal(false);
const [throwOnCancel, setThrowOnCancel] = createSignal(false);
const [swapOnDown, setSwapOnDown] = createSignal(false);
const [swapped, setSwapped] = createSignal(false);
const [appTaps, setAppTaps] = createSignal(0);
const [listenLate, setListenLate] = createSignal(false);
const [listenLateDown, setListenLateDown] = createSignal(false);
const [listenLateHub, setListenLateHub] = createSignal(false);
const [listenLateText, setListenLateText] = createSignal(false);
const [queueOnDown, setQueueOnDown] = createSignal(false);
let lateOff: (() => void)[] = [];
let lateArea: WindowArea | null = null;
let outsideNode: HostNode | null = null;
let lateHost: Host | null = null;

class Counts {
	editor: int32 = 0;
	editorLeave: int32 = 0;
	app: int32 = 0;
	shell: int32 = 0;
	shellUp: int32 = 0;
	replacement: int32 = 0;
	replacementUp: int32 = 0;
	appUp: int32 = 0;
	layerHits: int32 = 0;
	areaPointers: int32 = 0;
	areaTexts: int32 = 0;
	lateUp: int32 = 0;
	lateDown: int32 = 0;
	lateHub: int32 = 0;
	lateText: int32 = 0;
	appText: int32 = 0;
	typed: string = "";
	editorTyped: string = "";
}

let counts = new Counts();

function editorPane(): NeonNode {
	return <View style={{ width: 200 }}>
		<Pressable style={{ width: 100, height: 40 }} onPress={(): void => { counts.editor += 1; }}
			onHoverOut={(): void => { counts.editorLeave += 1; }}><Text>edit</Text></Pressable>
		<TextInput style={{ width: 100, height: 30 }} onChangeText={(t: string): void => { counts.editorTyped = t; }} />
	</View>;
}

function appPane(): NeonNode {
	return <View style={{ width: 200 }}>
		<View style={{ flexDirection: "column" }}
			onPointerUp={(): void => { counts.appUp += 1; }}
			onPointerDown={(): void => { if (listenLateDown()) { listenOutside("onPointerDown", (): void => { counts.lateDown += 1; }); } }}
			onTouchStart={(): void => { if (throwOnDown()) { throw new Error("app down failed"); } }}
			onTouchCancel={(): void => { if (throwOnCancel()) { throw new Error("app cancel failed"); } }}>
			<Show when={appShown() && !swapped()}>
				<Pressable style={{ width: 100, height: 40 }}
					onPressIn={(): void => {
						if (swapOnDown()) { setSwapped(true); }
						if (listenLate()) { listenOutside("onPointerUp", (): void => { counts.lateUp += 1; }); }
						if (queueOnDown()) { deliverPointer(lateArea as WindowArea, { kind: AreaPointerKind.Motion, pixelX: 250.0, pixelY: 20.0, button: 0 as int32, pressed: false, dx: 0.0, dy: 0.0 }); }
						if (listenLateHub()) { lateOff.push((lateArea as WindowArea).hub.handle.onPointer((e: AreaPointerEvent): void => { counts.lateHub += 1; })); }
					}}
					onPress={(): void => {
						if (throwOnPress()) { throw new Error("app handler failed"); }
						counts.app += 1;
						setAppTaps(appTaps() + 1);
					}}><Text>{`app ${appTaps()}`}</Text></Pressable>
			</Show>
			<Show when={appShown() && swapped()}>
				<View style={{ flexDirection: "column" }} onPointerUp={(): void => { counts.replacementUp += 1; }}>
					<Pressable style={{ width: 100, height: 40 }} onPress={(): void => { counts.replacement += 1; }}><Text>replacement</Text></Pressable>
				</View>
			</Show>
		</View>
		<TextInput style={{ width: 100, height: 30 }} onChangeText={(t: string): void => { counts.typed = t; }} />
		<View style={{ width: 100, height: 20 }} focusable
			onTextInput={(): void => {
				counts.appText += 1;
				if (listenLateText()) { listenOutside("onTextInput", (): void => { counts.lateText += 1; }); }
			}} />
	</View>;
}

function listenOutside(name: string, run: () => void): void {
	createRoot((dispose: () => void): void => {
		(lateHost as Host).addEvent(outsideNode as HostNode, name, (e: NeonEvent): void => { run(); });
		lateOff.push(dispose);
	});
}

function unlisten(): void {
	for (const off of lateOff) { off(); }
	lateOff = [];
}

function shellPanes(): NeonNode {
	return <View style={{ flexDirection: "column" }} onPointerUp={(): void => { counts.shellUp += 1; }}>
		<Pressable style={{ flexDirection: "row" }} onPress={(): void => { counts.shell += 1; }}>{editorPane()}{appPane()}</Pressable>
	</View>;
}

function plainPanes(): NeonNode {
	return <View style={{ flexDirection: "column" }}>
		<View style={{ flexDirection: "row" }}>{editorPane()}{appPane()}</View>
	</View>;
}

function mount(shell: boolean): Fixture {
	counts = new Counts();
	setOverlay(false);
	setAppShown(true);
	setThrowOnPress(false);
	setThrowOnDown(false);
	setThrowOnCancel(false);
	setSwapOnDown(false);
	setSwapped(false);
	setAppTaps(0);
	setListenLate(false);
	setListenLateDown(false);
	setListenLateHub(false);
	setListenLateText(false);
	setQueueOnDown(false);
	lateOff = [];
	resetErrorHalt();
	const areas: WindowArea[] = [];
	const panes = shell ? shellPanes() : plainPanes();
	const dispose = render(element(
		<Void>
			{panes}
			<Show when={overlay()}>
				<View style={{ position: "absolute", left: 200, top: 0, width: 200, height: 200 }} />
			</Show>
		</Void>
	), windowHost(testWindow(areas)), windowNode("window"));
	const area = areas[0];
	outsideNode = area.vh.tree.childrenOf(area.vh.root as VoidNode)[0] as unknown as HostNode;
	lateHost = area.vh.host;
	lateArea = area;
	const row = area.vh.tree.childrenOf(area.vh.tree.childrenOf(area.vh.root as VoidNode)[0])[0];
	const editor = openDevScope(area.vh.host, area.vh.tree.childrenOf(row)[0] as unknown as HostNode);
	const app = openDevScope(area.vh.host, area.vh.tree.childrenOf(row)[1] as unknown as HostNode);
	if (!editor.ok || !app.ok) { throw new Error("the scopes did not open"); }
	return new Fixture(area, editor.value, app.value, dispose);
}

function laid(f: Fixture): void {
	deliverResize(f.area, 640 as int32, 360 as int32, 1.0);
	f.area.vh.layout(f.area.logicalWidth(), f.area.logicalHeight());
}

function treeOf(scope: DevScope): ScopeTree {
	const t = scopeTree(scope, { maxNodes: 100 as int32, maxDepth: 10 as int32 });
	if (!t.ok) { throw new Error(`tree refused: ${t.error.detail}`); }
	return t.value;
}

function find(n: ScopeNode, test: (n: ScopeNode) => boolean): DevRef | null {
	if (test(n)) { return n.ref; }
	for (const c of n.children) {
		const got = find(c, test);
		if (got !== null) { return got; }
	}
	return null;
}

function pressableIn(scope: DevScope): DevRef {
	const r = find(treeOf(scope).root, (n: ScopeNode): boolean => n.pressable && n.tag === "pressable");
	if (r === null) { throw new Error("no pressable in the scope"); }
	return r as DevRef;
}

function inputIn(scope: DevScope): DevRef {
	const r = find(treeOf(scope).root, (n: ScopeNode): boolean => n.tag === "textinput");
	if (r === null) { throw new Error("no text input in the scope"); }
	return r as DevRef;
}

function reason<T>(r: Result<T, DevActRefusal>): string {
	return r.ok ? "ok" : r.error.reason.toString();
}

function why<T>(r: Result<T, DevActRefusal>): string {
	return r.ok ? "ok" : `${r.error.reason.toString()}: ${r.error.detail}`;
}

function count(n: ScopeNode): int32 {
	let total: int32 = 1;
	for (const c of n.children) { total += count(c); }
	return total;
}

function centreOf(n: ScopeNode, ref: DevRef): float64[] | null {
	if (n.ref.node === ref.node) { return [(n.x + n.w / 2.0) as float64, (n.y + n.h / 2.0) as float64]; }
	for (const c of n.children) {
		const got = centreOf(c, ref);
		if (got !== null) { return got; }
	}
	return null;
}

function centre(scope: DevScope, ref: DevRef): float64[] {
	const got = centreOf(treeOf(scope).root, ref);
	if (got === null) { throw new Error("the ref is not in the scope's tree"); }
	return got as float64[];
}

test "a scope that was never laid out refuses its tree instead of inventing geometry" {
	const f = mount(false);
	assert reason(scopeTree(f.app, { maxNodes: 10 as int32, maxDepth: 4 as int32 })) === DevRefusal.NotLaidOut.toString(), "not laid out";
	f.dispose();
}

test "a scope's tree walks only its own subtree and stops at the limit while walking" {
	const f = mount(false);
	laid(f);
	const whole = treeOf(f.app);
	assert !whole.truncated && count(whole.root) === f.app.issued.length, `the app subtree whole: ${count(whole.root)} nodes`;
	assert find(whole.root, (n: ScopeNode): boolean => n.text === "edit") === null, "the editor's nodes are not in the app scope";
	const cut = scopeTree(f.app, { maxNodes: 2 as int32, maxDepth: 10 as int32 });
	assert cut.ok && cut.value.truncated && f.app.issued.length === 2, `stopped at two: ${f.app.issued.length}`;
	f.dispose();
}

test "a press in the app scope runs the app's handler and nothing outside the scope hears it" {
	const f = mount(false);
	laid(f);
	const r = scopePress(f.app, pressableIn(f.app));
	const said = why<void>(r);
	assert r.ok, `delivered: ${said}`;
	assert counts.app === 1 && counts.appUp === 1 && counts.editor === 0 && counts.editorLeave === 0, `app ${counts.app}, app up ${counts.appUp}, editor ${counts.editor}, editor leave ${counts.editorLeave}`;
	f.dispose();
}

test "a press under a shell that listens above the scope is refused before any handler runs" {
	const f = mount(true);
	laid(f);
	const r = scopePress(f.app, pressableIn(f.app));
	assert reason(r) === DevRefusal.Intercepted.toString(), "intercepted: " + why<void>(r);
	assert counts.app === 0 && counts.shell === 0 && counts.shellUp === 0, `nothing ran: app ${counts.app}, shell ${counts.shell}, shell up ${counts.shellUp}`;
	f.dispose();
}

test "a press that would make a hovered editor node hear its pointer leave is refused" {
	const f = mount(false);
	laid(f);
	const at = centre(f.editor, pressableIn(f.editor));
	deliverPointer(f.area, { kind: AreaPointerKind.Motion, pixelX: at[0], pixelY: at[1], button: 0 as int32, pressed: false, dx: 0.0, dy: 0.0 });
	const queued = scopePress(f.app, pressableIn(f.app));
	assert reason(queued) === DevRefusal.Busy.toString(), "a motion waiting for its frame makes the press busy: " + why<void>(queued);
	drainInput(f.area);
	const r = scopePress(f.app, pressableIn(f.app));
	assert reason(r) === DevRefusal.Intercepted.toString(), "intercepted: " + why<void>(r);
	assert counts.editorLeave === 0 && counts.app === 0, `no leave and no press: leave ${counts.editorLeave}, app ${counts.app}`;
	f.dispose();
}

test "limits that would walk nothing are refused before anything is read" {
	const f = mount(false);
	assert reason(scopeTree(f.app, { maxNodes: 0 as int32, maxDepth: 4 as int32 })) === DevRefusal.InvalidLimits.toString(), "no nodes";
	assert reason(scopeTree(f.app, { maxNodes: 4 as int32, maxDepth: -1 as int32 })) === DevRefusal.InvalidLimits.toString(), "negative depth";
	f.dispose();
}

test "a node moved out of its scope is refused as outside the scope" {
	const f = mount(false);
	laid(f);
	const moved = pressableIn(f.app);
	f.area.vh.host.append(f.editor.root as unknown as HostNode, moved.node as unknown as HostNode);
	assert reason(scopePress(f.app, moved)) === DevRefusal.OutsideScope.toString(), "outside the scope";
	assert counts.app === 0 && counts.editor === 0, "nothing ran";
	f.dispose();
}

test "an area layer that takes pointer input or an area-wide listener makes presses and typing unsupported, and none of them hears anything" {
	const f = mount(false);
	laid(f);
	const anchor: LayerAnchor = { node: f.area.vh.root as unknown, inText: false };
	const off = f.area.hub.addLayer({
		anchor,
		layout: (w: int32, h: int32): void => {},
		prepare: (w: int32, h: int32): void => {},
		draw: (): void => {},
		hit: (x: float32, y: float32, kind: AreaPointerKind, e: NeonEvent): boolean => { counts.layerHits += 1; return true; },
	});
	assert reason(scopePress(f.app, pressableIn(f.app))) === DevRefusal.Unsupported.toString(), "a layer that hits";
	off();
	const offPointer = f.area.hub.handle.onPointer((e: AreaPointerEvent): void => { counts.areaPointers += 1; });
	assert reason(scopePress(f.app, pressableIn(f.app))) === DevRefusal.Unsupported.toString(), "an area pointer listener";
	offPointer();
	assert scopePress(f.app, inputIn(f.app)).ok, "with neither, the app field takes focus";
	const offText = f.area.hub.handle.onText((t: string): void => { counts.areaTexts += 1; });
	assert reason(scopeType(f.app, inputIn(f.app), "x")) === DevRefusal.Unsupported.toString(), "an area text listener";
	offText();
	assert counts.layerHits === 0 && counts.areaPointers === 0 && counts.areaTexts === 0 && counts.app === 0 && counts.typed === "",
		`nothing heard: layer ${counts.layerHits}, pointer ${counts.areaPointers}, text ${counts.areaTexts}, app ${counts.app}`;
	f.dispose();
}

test "a listener added outside the scope during the down is never called, the gesture is cleared, and the next press works" {
	const f = mount(false);
	laid(f);
	setListenLate(true);
	flush();
	const r = scopePress(f.app, pressableIn(f.app));
	assert reason(r) === DevRefusal.ForeignListenerBlocked.toString() && !r.ok && r.error.detail.indexOf("started listening during the press") > 0, "blocked before the release: " + why<void>(r);
	assert counts.lateUp === 0 && counts.appUp === 0 && counts.app === 0, `nothing released: late ${counts.lateUp}, app up ${counts.appUp}, app ${counts.app}`;
	assert f.area.held === (0 as int32), "the gesture was cleared";
	setListenLate(false);
	unlisten();
	flush();
	assert scopePress(f.app, pressableIn(f.app)).ok, "the next press works";
	flush();
	laid(f);
	assert find(treeOf(f.app).root, (n: ScopeNode): boolean => n.text === "app 1") !== null && counts.lateUp === 0, "the tree shows app 1, and the removed listener never ran";
	f.dispose();
}

test "a listener added during the down on an outside ancestor not yet reached never runs" {
	const f = mount(false);
	laid(f);
	setListenLateDown(true);
	flush();
	const r = scopePress(f.app, pressableIn(f.app));
	assert reason(r) === DevRefusal.ForeignListenerBlocked.toString() && !r.ok && r.error.detail.indexOf("onPointerDown outside the scope was not called") > 0, "blocked in the down: " + why<void>(r);
	assert counts.lateDown === 0 && counts.app === 0 && f.area.held === (0 as int32), `never ran: late down ${counts.lateDown}, app ${counts.app}, held ${f.area.held}`;
	setListenLateDown(false);
	unlisten();
	flush();
	assert scopePress(f.app, pressableIn(f.app)).ok && counts.app === 1, `the next press works: ${counts.app}`;
	f.dispose();
}

test "an area pointer subscriber added during the down never hears the release or the cleanup" {
	const f = mount(false);
	laid(f);
	setListenLateHub(true);
	flush();
	const r = scopePress(f.app, pressableIn(f.app));
	assert reason(r) === DevRefusal.ForeignListenerBlocked.toString() && !r.ok && r.error.detail.indexOf("the area outside the scope started listening") === 0, "stopped before the release by the new subscriber: " + why<void>(r);
	assert counts.lateHub === 0 && counts.app === 0 && f.area.held === (0 as int32), `never heard: hub ${counts.lateHub}, app ${counts.app}, held ${f.area.held}`;
	setListenLateHub(false);
	unlisten();
	flush();
	assert scopePress(f.app, pressableIn(f.app)).ok && counts.app === 1 && counts.lateHub === 0, `the next press works: ${counts.app}`;
	f.dispose();
}

test "text bubbling to a listener added outside the scope during the same text never reaches it" {
	const f = mount(false);
	laid(f);
	const field = find(treeOf(f.app).root, (n: ScopeNode): boolean => n.tag === "view" && n.w === 100.0 && n.h === 20.0);
	assert field !== null, "the focusable view is in the app scope";
	assert scopePress(f.app, field as DevRef).ok, "the view takes focus";
	setListenLateText(true);
	flush();
	const r = scopeType(f.app, field as DevRef, "x");
	assert reason(r) === DevRefusal.ForeignListenerBlocked.toString() && !r.ok && r.error.detail.indexOf("onTextInput outside the scope was not called") > 0, `blocked in the bubble: ${why<void>(r)} (app text ${counts.appText}, late ${counts.lateText})`;
	assert counts.appText === 1 && counts.lateText === 0, `the app heard it, the outside listener did not: app ${counts.appText}, late ${counts.lateText}`;
	setListenLateText(false);
	unlisten();
	flush();
	assert scopeType(f.app, field as DevRef, "y").ok && counts.appText === 2 && counts.lateText === 0, `the next text works: ${counts.appText}`;
	f.dispose();
}

test "an editor ref handed to the app scope is refused as foreign" {
	const f = mount(false);
	laid(f);
	const editorRef = pressableIn(f.editor);
	assert reason(scopePress(f.app, editorRef)) === DevRefusal.ForeignScope.toString(), "foreign";
	assert counts.editor === 0, "nothing was pressed";
	f.dispose();
}

test "an overlay above the target makes the press refused as intercepted, and no handler runs" {
	const f = mount(false);
	laid(f);
	const target = pressableIn(f.app);
	setOverlay(true);
	flush();
	laid(f);
	const r = scopePress(f.app, target);
	assert reason(r) === DevRefusal.Intercepted.toString(), "intercepted: " + why<void>(r);
	assert !r.ok && r.error.hit === null, "the hit is outside the scope";
	assert counts.app === 0, "the app handler did not run";
	f.dispose();
}

test "a removed node and a node the latest tree did not hand out are refused by name" {
	const f = mount(false);
	laid(f);
	const old = pressableIn(f.app);
	scopeTree(f.app, { maxNodes: 1 as int32, maxDepth: 10 as int32 });
	assert reason(scopePress(f.app, old)) === DevRefusal.NotIssued.toString(), "not issued after a smaller tree";
	pressableIn(f.app);
	setAppShown(false);
	flush();
	assert reason(scopePress(f.app, old)) === DevRefusal.Removed.toString(), "removed";
	setAppShown(true);
	flush();
	laid(f);
	assert reason(scopePress(f.app, old)) === DevRefusal.Removed.toString(), "the old ref does not rebind to the remounted node";
	assert scopePress(f.app, pressableIn(f.app)).ok, "a fresh ref to the remounted node presses";
	f.dispose();
}

test "typing needs the target's focus; a focused editor field refuses typing and a press that would blur it" {
	const f = mount(false);
	laid(f);
	assert reason(scopeType(f.app, inputIn(f.app), "x")) === DevRefusal.NotFocused.toString(), "nothing focused";
	assert scopePress(f.editor, inputIn(f.editor)).ok, "the editor field takes focus";
	assert reason(scopeType(f.app, inputIn(f.app), "x")) === DevRefusal.ForeignFocus.toString(), "foreign focus";
	assert reason(scopePress(f.app, inputIn(f.app))) === DevRefusal.Intercepted.toString(), "pressing the app field would blur the editor field";
	assert counts.typed === "" && counts.editorTyped === "", "nothing was typed";
	f.area.vh.focus(null);
	assert scopePress(f.app, inputIn(f.app)).ok, "with no foreign focus the app field takes focus";
	const r = scopeType(f.app, inputIn(f.app), "hi");
	assert r.ok && counts.typed === "hi", `typed into the app: ${counts.typed} (${why<void>(r)})`;
	f.dispose();
}

test "a release whose handler throws is reported as failed, and the scope keeps working" {
	const f = mount(false);
	laid(f);
	setThrowOnPress(true);
	const r = scopePress(f.app, pressableIn(f.app));
	assert reason(r) === DevRefusal.HandlerFailed.toString() && !r.ok && r.error.detail.indexOf("app handler failed") === 0, "failed: " + why<void>(r);
	assert f.area.held === (0 as int32), "no button is left held";
	setThrowOnPress(false);
	assert scopePress(f.app, pressableIn(f.app)).ok && counts.app === 1, `recovered: ${counts.app}`;
	flush();
	laid(f);
	assert find(treeOf(f.app).root, (n: ScopeNode): boolean => n.text === "app 1") !== null, "the tree shows the recovered press without a reset";
	f.dispose();
}

test "a down that throws and a cancel that throws are both reported, inside the result" {
	const f = mount(false);
	laid(f);
	setThrowOnDown(true);
	setThrowOnCancel(true);
	const r = scopePress(f.app, pressableIn(f.app));
	assert reason(r) === DevRefusal.HandlerFailed.toString(), "failed: " + why<void>(r);
	assert !r.ok && r.error.detail.indexOf("app down failed") === 0 && r.error.detail.indexOf("app cancel failed") > 0, "both failures named: " + why<void>(r);
	assert f.area.held === (0 as int32) && counts.app === 0, `no button held, no press: held ${f.area.held}, app ${counts.app}`;
	setThrowOnDown(false);
	setThrowOnCancel(false);
	assert scopePress(f.app, pressableIn(f.app)).ok && counts.app === 1, `recovered: ${counts.app}`;
	flush();
	laid(f);
	assert find(treeOf(f.app).root, (n: ScopeNode): boolean => n.text === "app 1") !== null, "the tree shows the recovered press without a reset";
	f.dispose();
}

test "a target replaced during its press is reported as gone, and no release reaches the replacement" {
	const f = mount(false);
	laid(f);
	setSwapOnDown(true);
	const r = scopePress(f.app, pressableIn(f.app));
	assert reason(r) === DevRefusal.TargetGoneDuringPress.toString(), "gone: " + why<void>(r);
	assert counts.app === 0 && counts.appUp === 0 && counts.replacement === 0 && counts.replacementUp === 0, `nothing pressed or released: app ${counts.app}, app up ${counts.appUp}, replacement ${counts.replacement}, up ${counts.replacementUp}`;
	assert f.area.held === (0 as int32), "the area holds no button after the cancel";
	setSwapOnDown(false);
	setSwapped(false);
	flush();
	laid(f);
	assert scopePress(f.app, pressableIn(f.app)).ok && counts.app === 1, `input state was cleaned up, the next press lands: ${counts.app}`;
	f.dispose();
}

test "a button already held on the area makes a scoped press refused as busy, and that gesture is left alone" {
	const f = mount(false);
	laid(f);
	const at = centre(f.editor, pressableIn(f.editor));
	deliverPointer(f.area, { kind: AreaPointerKind.Button, pixelX: at[0], pixelY: at[1], button: 1 as int32, pressed: true, dx: 0.0, dy: 0.0 });
	assert reason(scopePress(f.app, pressableIn(f.app))) === DevRefusal.Busy.toString(), "busy";
	deliverPointer(f.area, { kind: AreaPointerKind.Button, pixelX: at[0], pixelY: at[1], button: 1 as int32, pressed: false, dx: 0.0, dy: 0.0 });
	assert counts.editor === 1 && counts.app === 0, `the held gesture completed as its own: editor ${counts.editor}, app ${counts.app}`;
	f.dispose();
}

test "a physical touch in progress (button 0, held 0) makes a scoped press busy, and the touch completes as its own" {
	const f = mount(false);
	laid(f);
	const target = pressableIn(f.app);
	const at = centre(f.app, target);
	deliverPointer(f.area, { kind: AreaPointerKind.Button, pixelX: at[0], pixelY: at[1], button: 0 as int32, pressed: true, dx: 0.0, dy: 0.0 });
	assert f.area.held === (0 as int32), "a touch leaves held at 0";
	assert reason(scopePress(f.app, pressableIn(f.app))) === DevRefusal.Busy.toString(), "busy while the touch is down";
	assert counts.app === 0 && counts.appUp === 0, `no synthetic callbacks: app ${counts.app}, app up ${counts.appUp}`;
	deliverPointer(f.area, { kind: AreaPointerKind.Button, pixelX: at[0], pixelY: at[1], button: 0 as int32, pressed: false, dx: 0.0, dy: 0.0 });
	assert counts.app === 1 && counts.appUp === 1, `the touch completed once as its own: app ${counts.app}, app up ${counts.appUp}`;
	f.dispose();
}

test "left down, right down, right up leaves held 0 with the left gesture captured, and a scoped press stays busy" {
	const f = mount(false);
	laid(f);
	const at = centre(f.app, pressableIn(f.app));
	const button = (b: int32, pressed: boolean): void => {
		deliverPointer(f.area, { kind: AreaPointerKind.Button, pixelX: at[0], pixelY: at[1], button: b, pressed, dx: 0.0, dy: 0.0 });
	};
	button(1 as int32, true);
	button(2 as int32, true);
	button(2 as int32, false);
	assert f.area.held === (0 as int32), "held reads 0 after the right release";
	assert reason(scopePress(f.app, pressableIn(f.app))) === DevRefusal.Busy.toString(), "busy while the left gesture is captured";
	assert counts.app === 0, `no synthetic press: app ${counts.app}`;
	button(1 as int32, false);
	assert counts.app === 1, `the left gesture completed once as its own: app ${counts.app}`;
	f.dispose();
}

test "physical input queued during the down stops the press before the release and stays queued for its frame" {
	const f = mount(false);
	laid(f);
	setQueueOnDown(true);
	flush();
	const r = scopePress(f.app, pressableIn(f.app));
	assert reason(r) === DevRefusal.Busy.toString() && !r.ok && r.error.detail.indexOf("arrived during the operation") > 0, "busy at the release: " + why<void>(r);
	assert counts.app === 0 && counts.appUp === 0 && f.area.held === (0 as int32), `no release, gesture cleared: app ${counts.app}, up ${counts.appUp}, held ${f.area.held}`;
	assert f.area.queued.length === 1, `the physical motion is still queued: ${f.area.queued.length}`;
	drainInput(f.area);
	assert f.area.queued.length === 0, "its frame drained it";
	setQueueOnDown(false);
	flush();
	assert scopePress(f.app, pressableIn(f.app)).ok && counts.app === 1, `the next press works: ${counts.app}`;
	f.dispose();
}

test "closing one scope leaves the other working, and releasing the area closes both" {
	const f = mount(false);
	laid(f);
	closeScope(f.app);
	assert reason(scopeTree(f.app, { maxNodes: 10 as int32, maxDepth: 4 as int32 })) === DevRefusal.ScopeClosed.toString(), "closed";
	assert scopePress(f.editor, pressableIn(f.editor)).ok && counts.editor === 1, "the editor scope still presses";
	f.dispose();
	assert reason(scopeTree(f.editor, { maxNodes: 10 as int32, maxDepth: 4 as int32 })) === DevRefusal.ScopeClosed.toString(), "the area's release closed it";
}

test "a host that is not an open Void area, or a node outside it, opens no scope" {
	const f = mount(false);
	const other = mount(false);
	const r = openDevScope(f.area.vh.host, other.area.vh.root);
	assert !r.ok && r.error === DevScopeError.NotInArea, "a node of another area";
	f.dispose();
	const gone = openDevScope(f.area.vh.host, f.area.vh.root);
	assert !gone.ok && gone.error === DevScopeError.NotAVoidArea, "a released area";
	other.dispose();
}
