// ref — the escape hatch to the host node. The callback fires once per mount
// with the node the element became.
//
// Ordering follows REACT, not Solid, decided 2026-09-18 after reading both: ref is
// component/event surface, and the standing rule is reactivity = Solid, component and
// event surface = React Native. React attaches refs innermost-first, after the subtree
// is built (`~/projects/react/packages/react-reconciler/src/ReactFiberCommitWork.js`:
// recursivelyTraverseLayoutEffects `:682` `:627` before safelyAttachRef `:700` `:641`).
// Solid is the one that differs — dom-expressions unshifts `use(ref, el)` onto the
// element's own exprs (`packages/babel-plugin-jsx-dom-expressions/src/dom/element.js`
// `:676` `:694` `:704`) while transformChildren pushes each child's afterwards
// (`:1122`), so a parent's ref runs BEFORE any child's. The cells below pin React's
// order: innermost-first, and a ref already sees a bound reactive child. What all three
// agree on: ref fires before the site root is placed.

import { createSignal } from "../../src/core/signal";
import { createEffect, onSettled } from "../../src/core/effect";
import { Cleanup } from "../../src/core/types";
import { createRoot } from "../../src/core/owner";
import { onCleanup } from "../../src/core/cleanup";
import { element } from "../../src/macros/ui/element";
import { NeonNode } from "../../src/render/node";
import { HostNode, MockNode, mockNode, mockHost, render, mockToString, fireEvent } from "../../src/render/host";
import { View, ViewHandle, TextInput, TextInputHandle, Pressable, Text } from "../../src/components/primitives";
import { NeonEvent } from "../../src/render/event";
import { flush } from "../../src/core/runtime";
import { ElementHandle, MeasureRect, MeasureError } from "../../src/render/measure";
import { Image } from "../../src/components/image";

test "ref hands the completed host node to the callback" {
	let seen = "";
	const grab: (n: HostNode) => void = (n) => { seen = mockToString(n as unknown as MockNode); };
	const root: MockNode = mockNode("root");
	const view: NeonNode = element(<div class="box"><p ref={grab}>hi</p></div>);
	render(view, mockHost(), root as unknown as HostNode);
	assert seen === "<p>hi</p>", "ref saw the finished node, seen=" + seen;
	assert mockToString(root) === "<root><div class=\"box\"><p>hi</p></div></root>", "ref leaves no attribute behind: " + mockToString(root);
}

test "ref on the root element of a site" {
	let tag = "";
	const grab: (n: HostNode) => void = (n) => { tag = (n as unknown as MockNode).tag; };
	const root: MockNode = mockNode("root");
	render(element(<section ref={grab}>x</section>), mockHost(), root as unknown as HostNode);
	assert tag === "section", "root ref, tag=" + tag;
	assert mockToString(root) === "<root><section>x</section></root>", "golden: " + mockToString(root);
}

test "ref reaches the universal vocabulary, not just raw tags" {
	let viewTag = "";
	let inputTag = "";
	const grabView: (h: ViewHandle) => void = (h) => { viewTag = (h.node as unknown as MockNode).tag; };
	const grabInput = (h: TextInputHandle): void => { inputTag = (h.node as unknown as MockNode).tag; };
	const root: MockNode = mockNode("root");
	render(element(<View ref={grabView}><TextInput ref={grabInput} /></View>), mockHost(), root as unknown as HostNode);
	assert viewTag === "view", "View ref, tag=" + viewTag;
	assert inputTag === "textinput", "TextInput ref, tag=" + inputTag;
}

test "ref fires after a reactive child is bound" {
	const [n, _setN] = createSignal(7);
	let seen = "";
	const grab: (h: HostNode) => void = (h) => { seen = mockToString(h as unknown as MockNode); };
	const root: MockNode = mockNode("root");
	render(element(<p ref={grab}>{n().toString()}</p>), mockHost(), root as unknown as HostNode);
	assert seen === "<p>7</p>", "ref saw the bound child, seen=" + seen;
}

test "a callback prop crosses raw when it is named, not only when it is a literal" {
	let hits = 0;
	const inc: (e: NeonEvent) => void = (e) => { hits = hits + 1; };
	let seenTag = "";
	const grab = (h: ElementHandle): void => { seenTag = (h.node as unknown as MockNode).tag; };
	const root: MockNode = mockNode("root");
	render(element(<Pressable onPress={inc} ref={grab}><Text>+</Text></Pressable>), mockHost(), root as unknown as HostNode);
	fireEvent(root.children[0], "onPress");
	flush();
	assert hits === 1, "named handler ran, hits=" + hits.toString();
	assert seenTag === "pressable", "named ref ran, tag=" + seenTag;
}

test "an inline arrow ref crosses raw" {
	let seen = "";
	const root: MockNode = mockNode("root");
	render(element(<p ref={(n: HostNode) => { seen = (n as unknown as MockNode).tag; }}>hi</p>), mockHost(), root as unknown as HostNode);
	assert seen === "p", "inline arrow ref fired, seen=" + seen;
}

test "ref fires before the site root is placed" {
	const root: MockNode = mockNode("root");
	let kidsAtRef = -1;
	const grab: (h: HostNode) => void = (h) => { kidsAtRef = root.children.length; };
	render(element(<div ref={grab}><p>hi</p></div>), mockHost(), root as unknown as HostNode);
	assert kidsAtRef === 0, "ref ran before the root was placed, kids=" + kidsAtRef.toString();
}

test "nested refs fire innermost first, each with its own children complete" {
	let order = "";
	const root: MockNode = mockNode("root");
	const outer: (h: HostNode) => void = (h) => { order = order + "outer" + (h as unknown as MockNode).children.length.toString(); };
	const inner: (h: HostNode) => void = (h) => { order = order + "inner" + (h as unknown as MockNode).children.length.toString(); };
	render(element(<div ref={outer}><p ref={inner}>hi</p></div>), mockHost(), root as unknown as HostNode);
	assert order === "inner1outer1", "order=" + order;
}

test "innermost first and after its subtree, in the flat path too" {
	let order = "";
	let seen = "";
	const root: MockNode = mockNode("root");
	const outer: (h: HostNode) => void = (h) => { order = order + "outer"; seen = mockToString(h as unknown as MockNode); };
	const inner: (h: HostNode) => void = (h) => { order = order + "inner"; };
	render(element(<div class="box" ref={outer}><View ref={inner}><Text>x</Text></View></div>), mockHost(), root as unknown as HostNode);
	assert order === "innerouter", "order=" + order;
	assert seen === "<div class=\"box\"><view><text>x</text></view></div>", "outer saw its finished subtree: " + seen;
}

test "a nested ref sees its parent inside the template" {
	let parentTag = "?";
	const root: MockNode = mockNode("root");
	const grab: (h: HostNode) => void = (h) => {
		const p = (h as unknown as MockNode).parent;
		parentTag = p === null ? "<none>" : p.tag;
	};
	render(element(<div><p ref={grab}>hi</p></div>), mockHost(), root as unknown as HostNode);
	assert parentTag === "div", "nested ref sees its parent, parent=" + parentTag;
}

function viewStamp(log: string[], name: string): (h: ViewHandle) => void {
	return (h: ViewHandle): void => { log.push(name); };
}

function stamp(log: string[], name: string): (h: HostNode) => void {
	return (h: HostNode): void => { log.push(name); };
}

test "ref={[a, b]} applies in source order, flattening nested arrays and nulls" {
	const log: string[] = [];
	const none: ((h: HostNode) => void) | null = null;
	const root: MockNode = mockNode("root");
	render(element(<p ref={[stamp(log, "a"), [stamp(log, "b"), none], stamp(log, "c")]}>hi</p>), mockHost(), root as unknown as HostNode);
	assert log.join(",") === "a,b,c", "order=" + log.join(",");
}

test "ref arrays work in the flat path and on a component" {
	const log: string[] = [];
	const root: MockNode = mockNode("root");
	render(element(<div ref={[stamp(log, "d1"), stamp(log, "d2")]}><View ref={[viewStamp(log, "v1"), viewStamp(log, "v2")]}><Text>x</Text></View></div>), mockHost(), root as unknown as HostNode);
	assert log.join(",") === "v1,v2,d1,d2", "order=" + log.join(",");
}

test "a typed handle ref takes an array" {
	const log: string[] = [];
	const a = (h: TextInputHandle): void => { log.push("a"); };
	const b = (h: TextInputHandle): void => { log.push("b"); };
	const root: MockNode = mockNode("root");
	render((h: Host, p: HostNode, bf: HostNode | null): void => {
		element(<TextInput ref={[a, b]} />)(h, p, bf);
	}, mockHost(), root as unknown as HostNode);
	assert log.join(",") === "a,b", "order=" + log.join(",");
}

test "ref apply is untracked: a signal read in it does not re-run the mount" {
	const [n, setN] = createSignal(0);
	let mounts = 0;
	const read: (h: HostNode) => void = (h) => { n(); };
	const root: MockNode = mockNode("root");
	createRoot((dispose) => {
		createEffect<int32>(
			(p: int32 | null): int32 => {
				mounts = mounts + 1;
				element(<p ref={read}>hi</p>)(mockHost(), root as unknown as HostNode, null);
				return 0;
			},
			(v: int32, p: int32 | null): Cleanup | null => null,
		);
		return 0;
	});
	setN(1);
	flush();
	assert mounts === 1, "mounts=" + mounts.toString();
}

function tooltip(log: string[], source: () => number): (h: HostNode) => void {
	log.push("setup");
	createEffect<number>(
		(p: number | null): number => source(),
		(value: number, p: number | null): Cleanup | null => { log.push("effect" + value.toString()); return null; },
	);
	onCleanup(() => { log.push("cleanup"); });
	return (h: HostNode): void => { log.push("apply" + source().toString()); };
}

test "a directive factory sets up in the current owner and applies as the returned function" {
	const [n, setN] = createSignal(1);
	const log: string[] = [];
	const root: MockNode = mockNode("root");
	const read = (): number => n();
	const dispose = render(element(<p ref={tooltip(log, read)}>hi</p>), mockHost(), root as unknown as HostNode);
	assert log.join(",") === "setup,apply1,effect1", "setup before apply, its effect after the mount: " + log.join(",");
	setN(2);
	flush();
	assert log.join(",") === "setup,apply1,effect1,effect2", "the setup effect lives on, the apply does not rerun: " + log.join(",");
	dispose();
	assert log.join(",") === "setup,apply1,effect1,effect2,cleanup", "the owner's disposal runs the setup cleanup: " + log.join(",");
}

function readingFactory(source: () => number): (h: HostNode) => void {
	source();
	return (h: HostNode): void => {};
}

test "a directive factory sets up untracked: a signal read in setup does not re-run the mount" {
	const [n, setN] = createSignal(0);
	let mounts = 0;
	const read = (): number => n();
	const root: MockNode = mockNode("root");
	createRoot((dispose) => {
		createEffect<int32>(
			(p: int32 | null): int32 => {
				mounts = mounts + 1;
				element(<p ref={readingFactory(read)}>hi</p>)(mockHost(), root as unknown as HostNode, null);
				return 0;
			},
			(v: int32, p: int32 | null): Cleanup | null => null,
		);
		return 0;
	});
	setN(1);
	flush();
	assert mounts === 1, "mounts=" + mounts.toString();
}

test "an array mixes a factory and a plain callback" {
	const log: string[] = [];
	const [n, _setN] = createSignal(5);
	const read = (): number => n();
	const root: MockNode = mockNode("root");
	render(element(<p ref={[tooltip(log, read), stamp(log, "plain")]}>hi</p>), mockHost(), root as unknown as HostNode);
	assert log.join(",") === "setup,apply5,plain,effect5", "order=" + log.join(",");
}

test "a cleanup registered in the apply phase belongs to the mounting owner" {
	const log: string[] = [];
	const grab: (h: HostNode) => void = (h) => { onCleanup(() => { log.push("apply cleanup"); }); };
	const root: MockNode = mockNode("root");
	const dispose = render(element(<p ref={grab}>hi</p>), mockHost(), root as unknown as HostNode);
	assert log.length === 0, "not yet";
	dispose();
	assert log.join(",") === "apply cleanup", log.join(",");
}

test "a directive factory with no owner stops with an error that names the case" {
	const log: string[] = [];
	const [n, _setN] = createSignal(1);
	const read = (): number => n();
	const mount = element(<p ref={tooltip(log, read)}>hi</p>);
	let refused = "";
	try {
		mount(mockHost(), mockNode("root") as unknown as HostNode, null);
	} catch (e) {
		refused = (e as Error).message;
	}
	assert refused.indexOf("a ref directive factory ran with no owner") === 0, "refused=" + refused;
}

test "a nested ref sees its parent in the flat path too" {
	let parentTag = "?";
	const root: MockNode = mockNode("root");
	const grab: (h: HostNode) => void = (h) => {
		const p = (h as unknown as MockNode).parent;
		parentTag = p === null ? "<none>" : p.tag;
	};
	render(element(<div><Text>x</Text><p ref={grab}>hi</p></div>), mockHost(), root as unknown as HostNode);
	assert parentTag === "div", "parent=" + parentTag;
}

test "a View's ref focuses it on mount, as a terminal focuses its grid when the window opens" {
	let log = "";
	let grid: ViewHandle | null = null;
	const Grid = (): NeonNode => {
		onSettled((): Cleanup | null => { (grid as ViewHandle).focus(); return null; });
		return <View ref={(h: ViewHandle): void => { grid = h; }} focusable={true}
			onFocus={(e: NeonEvent): void => { log += "focus;"; }} onBlur={(e: NeonEvent): void => { log += "blur;"; }} />;
	};
	const root: MockNode = mockNode("root");
	const dispose = render(element(<Grid />), mockHost(), root as unknown as HostNode);
	assert log === "focus;", "focused on mount: " + log;
	(grid as ViewHandle).blur();
	assert log === "focus;blur;", "blur: " + log;
	dispose();
	(grid as ViewHandle).focus();
	(grid as ViewHandle).blur();
	assert log === "focus;blur;", "focus and blur after unmount do nothing: " + log;
}

test "a View's ref measures text through its host, and refuses a host that cannot and a View that is gone" {
	let frame: ViewHandle | null = null;
	const root: MockNode = mockNode("root");
	const dispose = render(element(<View ref={(h: ViewHandle): void => { frame = h; }} />), mockHost(), root as unknown as HostNode);
	const m = (frame as ViewHandle).measureText("abcd", { fontSize: 10 });
	assert m.width === 20 && m.height === 12.5 && m.ascender === 10 && m.descender === 2.5, `mock measure ${m.width}x${m.height}`;
	dispose();
	let refused = "";
	try { (frame as ViewHandle).measureText("x", {}); } catch (e) { refused = e.toString(); }
	assert refused.indexOf("after the View unmounted") >= 0, "measure after unmount: " + refused;

	const blind = mockHost();
	blind.measureText = null;
	render(element(<View ref={(h: ViewHandle): void => { frame = h; }} />), blind, mockNode("root") as unknown as HostNode);
	refused = "";
	try { (frame as ViewHandle).measureText("x", {}); } catch (e) { refused = e.toString(); }
	assert refused.indexOf("needs a host that measures text") >= 0, "host with no measure: " + refused;
}

test "direct Text and Image handle refs apply untracked under the mounting owner" {
	for (const image of [false, true]) {
		const [read, write] = createSignal(0);
		const root = mockNode("root");
		const host = mockHost();
		host.measureInWindow = (n: HostNode): Result<MeasureRect, MeasureError> => Result.ok({ x: 1, y: 2, width: 3, height: 4 });
		const handles: ElementHandle[] = [];
		let mounts = 0;
		let seen = -1;
		let cleanups = 0;
		const grab = (handle: ElementHandle): void => {
			seen = read();
			handles.push(handle);
			onCleanup((): void => { cleanups += 1; });
		};
		const app = image ? Image({ ref: grab }) : Text({ ref: grab });
		const dispose = createRoot((end: () => void): () => void => {
			createEffect<int32>(
				(prev: int32 | null): int32 => {
					mounts += 1;
					app(host, root as unknown as HostNode, null);
					return 0;
				},
				(value: int32, prev: int32 | null): Cleanup | null => null,
			);
			return end;
		});
		assert mounts === 1 && handles.length === 1 && root.children.length === 1;
		assert seen === 0 && cleanups === 0;
		write(1);
		assert mounts === 1 && handles.length === 1 && root.children.length === 1,
			"a signal read in the public ref must not remount its builder";
		assert seen === 0 && cleanups === 0;
		const frame = (): string => {
			let got = "";
			handles[0].measureInWindow((x: number, y: number, width: number, height: number): void => { got = `${x},${y},${width},${height}`; });
			return got;
		};
		assert frame() === "1,2,3,4", "the mounted handle measures: " + frame();
		dispose();
		assert cleanups === 1, "ref cleanup stays under the mounting owner";
		assert frame() === "0,0,0,0", "the one public handle is disposed with that owner: " + frame();
	}
}
