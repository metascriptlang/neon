import { createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { flush, resetErrorHalt } from "../../src/core/runtime";
import { Show } from "../../src/macros/ui/flow";
import { render, HostNode } from "../../src/render/host";
import { NeonNode } from "../../src/render/hostTypes";
import { Void, View, Text, Pressable, TextInput } from "../../src/components/primitives";
import { VoidNode } from "../../src/platform/void/host";
import { AreaWindow, WindowArea, windowHost, windowNode, deliverPointer, deliverResize, drainInput, logicalWidth, logicalHeight } from "../../src/platform/void/windowHost";
import { AreaPointerKind } from "../../src/render/voidAreaHandle";
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

class Counts {
	editor: int32 = 0;
	editorLeave: int32 = 0;
	app: int32 = 0;
	shell: int32 = 0;
	shellUp: int32 = 0;
	replacement: int32 = 0;
	replacementUp: int32 = 0;
	appUp: int32 = 0;
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
			onTouchStart={(): void => { if (throwOnDown()) { throw new Error("app down failed"); } }}
			onTouchCancel={(): void => { if (throwOnCancel()) { throw new Error("app cancel failed"); } }}>
			<Show when={appShown() && !swapped()}>
				<Pressable style={{ width: 100, height: 40 }}
					onPressIn={(): void => { if (swapOnDown()) { setSwapped(true); } }}
					onPress={(): void => {
						if (throwOnPress()) { throw new Error("app handler failed"); }
						counts.app += 1;
					}}><Text>app</Text></Pressable>
			</Show>
			<Show when={appShown() && swapped()}>
				<View style={{ flexDirection: "column" }} onPointerUp={(): void => { counts.replacementUp += 1; }}>
					<Pressable style={{ width: 100, height: 40 }} onPress={(): void => { counts.replacement += 1; }}><Text>replacement</Text></Pressable>
				</View>
			</Show>
		</View>
		<TextInput style={{ width: 100, height: 30 }} onChangeText={(t: string): void => { counts.typed = t; }} />
	</View>;
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
	resetErrorHalt();
	setThrowOnPress(false);
	assert scopePress(f.app, pressableIn(f.app)).ok && counts.app === 1, `recovered: ${counts.app}`;
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
	resetErrorHalt();
	setThrowOnDown(false);
	setThrowOnCancel(false);
	assert scopePress(f.app, pressableIn(f.app)).ok && counts.app === 1, `recovered: ${counts.app}`;
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
