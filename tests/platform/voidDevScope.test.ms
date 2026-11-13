import { createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { flush, resetErrorHalt } from "../../src/core/runtime";
import { Show } from "../../src/macros/ui/flow";
import { render, HostNode } from "../../src/render/host";
import { Void, View, Text, Pressable, TextInput } from "../../src/components/primitives";
import { VoidNode } from "../../src/platform/void/host";
import { AreaWindow, WindowArea, windowHost, windowNode, deliverPointer, deliverResize, logicalWidth, logicalHeight } from "../../src/platform/void/windowHost";
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
	editorPresses: int32 = 0;
	appPresses: int32 = 0;
	typed: string = "";
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
const [throwing, setThrowing] = createSignal(false);
const [vanishOnDown, setVanishOnDown] = createSignal(false);
const [swapped, setSwapped] = createSignal(false);
let counts = { editor: 0, app: 0, shell: 0, shellUp: 0, replacement: 0, replacementUp: 0, typed: "", editorTyped: "" };

function mount(): Fixture {
	counts = { editor: 0, app: 0, shell: 0, shellUp: 0, replacement: 0, replacementUp: 0, typed: "", editorTyped: "" };
	setSwapped(false);
	setOverlay(false);
	setAppShown(true);
	setThrowing(false);
	setVanishOnDown(false);
	resetErrorHalt();
	const areas: WindowArea[] = [];
	const dispose = render(element(
		<Void>
			<View style={{ flexDirection: "column" }} onPointerUp={(): void => { counts.shellUp += 1; }}><Pressable style={{ flexDirection: "row" }} onPress={(): void => { counts.shell += 1; }}>
				<View style={{ width: 200 }}>
					<Pressable style={{ width: 100, height: 40 }} onPress={(): void => { counts.editor += 1; }}><Text>edit</Text></Pressable>
					<TextInput style={{ width: 100, height: 30 }} onChangeText={(t: string): void => { counts.editorTyped = t; }} />
				</View>
				<View style={{ width: 200 }}>
					<Show when={appShown() && !swapped()}>
						<Pressable style={{ width: 100, height: 40 }}
							onPressIn={(): void => { if (vanishOnDown()) { setSwapped(true); } }}
							onPress={(): void => {
								if (throwing()) { throw new Error("app handler failed"); }
								counts.app += 1;
							}}><Text>app</Text></Pressable>
					</Show>
					<Show when={appShown() && swapped()}>
						<View style={{ flexDirection: "column" }} onPointerUp={(): void => { counts.replacementUp += 1; }}><Pressable style={{ width: 100, height: 40 }}
							onPress={(): void => { counts.replacement += 1; }}><Text>replacement</Text></Pressable></View>
					</Show>
					<TextInput style={{ width: 100, height: 30 }} onChangeText={(t: string): void => { counts.typed = t; }} />
					<Text>caption</Text>
				</View>
			</Pressable></View>
			<Show when={overlay()}>
				<View style={{ position: "absolute", left: 200, top: 0, width: 200, height: 200 }} />
			</Show>
		</Void>
	), windowHost(testWindow(areas)), windowNode("window"));
	const area = areas[0];
	const row = area.vh.tree.childrenOf(area.vh.tree.childrenOf(area.vh.root as VoidNode)[0])[0];
	const editorRoot = area.vh.tree.childrenOf(row)[0];
	const appRoot = area.vh.tree.childrenOf(row)[1];
	const editor = openDevScope(area.vh.host, editorRoot as unknown as HostNode);
	const app = openDevScope(area.vh.host, appRoot as unknown as HostNode);
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
	const r = find(treeOf(scope).root, (n: ScopeNode): boolean => n.pressable && n.tag !== "textinput");
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

test "a scope that was never laid out refuses its tree instead of inventing geometry" {
	const f = mount();
	assert reason(scopeTree(f.app, { maxNodes: 10 as int32, maxDepth: 4 as int32 })) === DevRefusal.NotLaidOut.toString(), "not laid out";
	f.dispose();
}

test "a scope's tree walks only its own subtree and stops at the limit while walking" {
	const f = mount();
	laid(f);
	const whole = treeOf(f.app);
	assert !whole.truncated && count(whole.root) === f.app.issued.length, `the app subtree whole: ${count(whole.root)} nodes`;
	assert find(whole.root, (n: ScopeNode): boolean => n.text === "edit") === null, "the editor's nodes are not in the app scope";
	const cut = scopeTree(f.app, { maxNodes: 2 as int32, maxDepth: 10 as int32 });
	assert cut.ok && cut.value.truncated && f.app.issued.length === 2, `stopped at two: ${f.app.issued.length}`;
	f.dispose();
}

test "a press in the app scope runs the app's handler and leaves the editor alone" {
	const f = mount();
	laid(f);
	const target = pressableIn(f.app);
	const r = scopePress(f.app, target);
	const said = why<void>(r);
	assert r.ok, `delivered: ${said}`;
	assert counts.app === 1 && counts.editor === 0, `app ${counts.app}, editor ${counts.editor}`;
	f.dispose();
}

test "a press whose handler would be an ancestor outside the scope is refused, and that handler does not run" {
	const f = mount();
	laid(f);
	const caption = find(treeOf(f.app).root, (n: ScopeNode): boolean => n.text === "caption");
	assert caption !== null, "the caption is in the app scope";
	const r = scopePress(f.app, caption as DevRef);
	assert reason(r) === DevRefusal.Intercepted.toString(), "intercepted: " + reason(r);
	assert counts.shell === 0 && counts.app === 0, `no handler ran: shell ${counts.shell}, app ${counts.app}`;
	assert scopePress(f.app, pressableIn(f.app)).ok && counts.app === 1, "the next press in the app still lands";
	f.dispose();
}

test "an editor ref handed to the app scope is refused as foreign" {
	const f = mount();
	laid(f);
	const editorRef = pressableIn(f.editor);
	assert reason(scopePress(f.app, editorRef)) === DevRefusal.ForeignScope.toString(), "foreign";
	assert counts.editor === 0, "nothing was pressed";
	f.dispose();
}

test "an overlay above the target makes the press refused as intercepted, and no handler runs" {
	const f = mount();
	laid(f);
	const target = pressableIn(f.app);
	setOverlay(true);
	flush();
	laid(f);
	const r = scopePress(f.app, target);
	assert reason(r) === DevRefusal.Intercepted.toString(), "intercepted: " + reason(r);
	assert !r.ok && r.error.hit === null, "the hit is outside the scope";
	assert counts.app === 0, "the app handler did not run";
	f.dispose();
}

test "a removed node and a node the latest tree did not hand out are refused by name" {
	const f = mount();
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

test "typing needs the target's focus, and a focused editor field refuses it as foreign" {
	const f = mount();
	laid(f);
	const appInput = inputIn(f.app);
	assert reason(scopeType(f.app, appInput, "x")) === DevRefusal.NotFocused.toString(), "nothing focused";
	assert scopePress(f.editor, inputIn(f.editor)).ok, "the editor field takes focus";
	assert reason(scopeType(f.app, inputIn(f.app), "x")) === DevRefusal.ForeignFocus.toString(), "foreign focus";
	assert counts.typed === "" && counts.editorTyped === "", "nothing was typed";
	assert scopePress(f.app, inputIn(f.app)).ok, "the app field takes focus";
	const r = scopeType(f.app, inputIn(f.app), "hi");
	assert r.ok && counts.typed === "hi", `typed into the app: ${counts.typed} (${reason(r)})`;
	f.dispose();
}

test "a throwing handler is reported as failed and the scope keeps working" {
	const f = mount();
	laid(f);
	setThrowing(true);
	const r = scopePress(f.app, pressableIn(f.app));
	assert reason(r) === DevRefusal.HandlerFailed.toString() && !r.ok && r.error.detail === "app handler failed", "failed: " + reason(r);
	resetErrorHalt();
	setThrowing(false);
	assert scopePress(f.app, pressableIn(f.app)).ok && counts.app === 1, `recovered: ${counts.app}`;
	f.dispose();
}

test "a target replaced during its press is reported as gone, and no release reaches the replacement or the shell" {
	const f = mount();
	laid(f);
	setVanishOnDown(true);
	const r = scopePress(f.app, pressableIn(f.app));
	assert reason(r) === DevRefusal.TargetGoneDuringPress.toString(), "gone: " + reason(r);
	assert counts.app === 0 && counts.shell === 0 && counts.shellUp === 0, `no press or release outside: app ${counts.app}, shell ${counts.shell}, shell up ${counts.shellUp}`;
	assert counts.replacement === 0 && counts.replacementUp === 0, `the replacement heard nothing: ${counts.replacement}, up ${counts.replacementUp}`;
	assert f.area.held === (0 as int32), "the area holds no button after the cancel";
	setVanishOnDown(false);
	setSwapped(false);
	flush();
	laid(f);
	assert scopePress(f.app, pressableIn(f.app)).ok && counts.app === 1, `input state was cleaned up, the next press lands: ${counts.app}`;
	f.dispose();
}

test "a button already held on the area makes a scoped press refused as busy, and that gesture is left alone" {
	const f = mount();
	laid(f);
	const edit = treeOf(f.editor).root.children[0];
	const px = (edit.x + edit.w / 2.0) as float64;
	const py = (edit.y + edit.h / 2.0) as float64;
	deliverPointer(f.area, { kind: AreaPointerKind.Button, pixelX: px, pixelY: py, button: 1 as int32, pressed: true, dx: 0.0, dy: 0.0 });
	assert reason(scopePress(f.app, pressableIn(f.app))) === DevRefusal.Busy.toString(), "busy";
	deliverPointer(f.area, { kind: AreaPointerKind.Button, pixelX: px, pixelY: py, button: 1 as int32, pressed: false, dx: 0.0, dy: 0.0 });
	assert counts.editor === 1 && counts.app === 0, `the held gesture completed as its own: editor ${counts.editor}, app ${counts.app}`;
	f.dispose();
}

test "closing one scope leaves the other working, and releasing the area closes both" {
	const f = mount();
	laid(f);
	closeScope(f.app);
	assert reason(scopeTree(f.app, { maxNodes: 10 as int32, maxDepth: 4 as int32 })) === DevRefusal.ScopeClosed.toString(), "closed";
	assert scopePress(f.editor, pressableIn(f.editor)).ok && counts.editor === 1 && counts.shell === 0, "the editor scope still presses";
	f.dispose();
	assert reason(scopeTree(f.editor, { maxNodes: 10 as int32, maxDepth: 4 as int32 })) === DevRefusal.ScopeClosed.toString(), "the area's release closed it";
}

test "a host that is not an open Void area, or a node outside it, opens no scope" {
	const f = mount();
	const other = mount();
	const r = openDevScope(f.area.vh.host, other.area.vh.root);
	assert !r.ok && r.error === DevScopeError.NotInArea, "a node of another area";
	f.dispose();
	const gone = openDevScope(f.area.vh.host, f.area.vh.root);
	assert !gone.ok && gone.error === DevScopeError.NotAVoidArea, "a released area";
	other.dispose();
}
