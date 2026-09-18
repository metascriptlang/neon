import { el, text, dynText, NeonNode } from "../../src/render/node";
import { MockNode, mockHost, renderToHost, mockToString } from "../../src/render/host";
import { Host, HostNode } from "../../src/render/hostTypes";
import { For, Index, Show } from "../../src/macros/ui/flow";
import { createSignal, accessor, Accessor } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { createComponent } from "../../src/render/component";
import { createRoot } from "../../src/core/owner";

function listText(node: MockNode): string {
	let s = "";
	for (const c of node.children) {
		if (c.tag !== "") {
			for (const t of c.children) { s = s + t.text; }
		}
	}
	return s;
}

test "For reactive list reuses rows on reorder, creates only new" {
	createRoot((d) => {
		const [items, setItems] = createSignal<number[]>([1, 2, 3]);
		let creates = 0;
		const ul = el("ul", [], [], [
			For<number>({
				each: () => items(),
				children: (item, i) => { creates = creates + 1; return <li>{"" + item}</li>; },
			}),
		]);
		const host = mockHost();
		const root = host.createElement("root");
		renderToHost(ul, host, root);
		const ulNode = (root as unknown as MockNode).children[0];
		assert listText(ulNode) === "123", "initial";
		assert creates === 3, "3 rows created";
		setItems([3, 1, 2]);
		assert listText(ulNode) === "312", "reordered";
		assert creates === 3, "no new creates on reorder";
		setItems([3, 1, 2, 4]);
		assert listText(ulNode) === "3124", "append";
		assert creates === 4, "one create for new item";
		setItems([2]);
		assert listText(ulNode) === "2", "shrink";
		assert creates === 4, "no creates on removal";
		d();
	});
}

test "For fallback shows when empty" {
	createRoot((d) => {
		const [items, setItems] = createSignal<number[]>([1]);
		const ul = el("ul", [], [], [
			For<number>({
				each: () => items(),
				children: (item, i) => <li>{"" + item}</li>,
				fallback: <li>empty</li>,
			}),
		]);
		const host = mockHost();
		const root = host.createElement("root");
		renderToHost(ul, host, root);
		const ulNode = (root as unknown as MockNode).children[0];
		assert listText(ulNode) === "1", "has item";
		setItems([]);
		assert listText(ulNode) === "empty", "fallback shown";
		setItems([5]);
		assert listText(ulNode) === "5", "back to item";
		d();
	});
}

test "Index updates row value in place, no recreate" {
	createRoot((d) => {
		const [items, setItems] = createSignal<number[]>([1, 2, 3]);
		let creates = 0;
		const ul = el("ul", [], [], [
			Index<number>({
				each: () => items(),
				children: (item, i) => { creates = creates + 1; return <li>{"" + item()}</li>; },
			}),
		]);
		const host = mockHost();
		const root = host.createElement("root");
		renderToHost(ul, host, root);
		const ulNode = (root as unknown as MockNode).children[0];
		assert listText(ulNode) === "123", "initial";
		assert creates === 3, "3 created";
		setItems([9, 2, 3]);
		assert listText(ulNode) === "923", "value updated in place";
		assert creates === 3, "no recreate on value change";
		d();
	});
}

test "Index grows and shrinks with the list" {
	createRoot((d) => {
		const [items, setItems] = createSignal<number[]>([1]);
		const ul = el("ul", [], [], [
			Index<number>({
				each: () => items(),
				children: (item, i) => <li>{"" + item()}</li>,
			}),
		]);
		const host = mockHost();
		const root = host.createElement("root");
		renderToHost(ul, host, root);
		const ulNode = (root as unknown as MockNode).children[0];
		assert listText(ulNode) === "1", "initial row";
		setItems([1, 2]);
		assert listText(ulNode) === "12", "append mounts the new row: " + listText(ulNode);
		setItems([1, 2, 3]);
		assert listText(ulNode) === "123", "a second append too: " + listText(ulNode);
		setItems([1]);
		assert listText(ulNode) === "1", "shrinking removes the tail: " + listText(ulNode);
		d();
	});
}

test "Show swaps child/fallback and stays stable while true" {
	createRoot((d) => {
		const [n, setN] = createSignal(1);
		const div = el("div", [], [], [
			Show({
				when: () => n() > 0,
				children: <span>on</span>,
				fallback: <span>off</span>,
			}),
		]);
		const host = mockHost();
		const root = host.createElement("root");
		renderToHost(div, host, root);
		const divNode = (root as unknown as MockNode).children[0];

		assert divNode.children[0].children[0].text === "on", "initial on";
		const firstSpan = divNode.children[0];
		setN(2);
		assert divNode.children[0].children[0].text === "on", "still on";
		assert divNode.children[0] === firstSpan, "same node — not rebuilt while truthy";
		setN(0);
		assert divNode.children[0].children[0].text === "off", "fallback off";
		setN(5);
		assert divNode.children[0].children[0].text === "on", "on again";
		d();
	});
}

test "For fallback reactive scope is disposed when rows return" {
	createRoot((d) => {
		const [items, setItems] = createSignal<number[]>([]);
		const [label, setLabel] = createSignal("empty");
		let fbRuns = 0;
		const fbTick = (): string => { fbRuns = fbRuns + 1; return label(); };
		const ul = el("ul", [], [], [
			For<number>({
				each: () => items(),
				children: (item, i) => <li>{"" + item}</li>,
				fallback: <li>{fbTick()}</li>,
			}),
		]);
		const host = mockHost();
		const root = host.createElement("root");
		renderToHost(ul, host, root);
		assert fbRuns === 1, "fallback effect ran once when empty";
		setLabel("none");
		assert fbRuns === 2, "fallback effect reactive while shown";
		setItems([1]);
		setLabel("ignored");
		assert fbRuns === 2, "fallback effect disposed once rows returned";
		d();
	});
}

test "For fallback reactive scope is disposed with the list" {
	const [label, setLabel] = createSignal("empty");
	let fbRuns = 0;
	const fbTick = (): string => { fbRuns = fbRuns + 1; return label(); };
	createRoot((d) => {
		const [items, setItems] = createSignal<number[]>([]);
		const ul = el("ul", [], [], [
			For<number>({
				each: () => items(),
				children: (item, i) => <li>{"" + item}</li>,
				fallback: <li>{fbTick()}</li>,
			}),
		]);
		const host = mockHost();
		const root = host.createElement("root");
		renderToHost(ul, host, root);
		assert fbRuns === 1, "fallback effect ran once when empty";
		d();
	});
	setLabel("after");
	assert fbRuns === 1, "fallback effect disposed with the list that showed it";
}

test "an accessor feeds For.each directly and the row index is an Accessor" {
	createRoot((d) => {
		const [items, setItems] = createSignal<number[]>([7, 8]);
		const ul = el("ul", [], [], [
			For<number>({
				each: items,
				children: (item, i) => {
					const idx: Accessor<number> = i;
					return <li>{"" + item + "@" + idx()}</li>;
				},
			}),
		]);
		const host = mockHost();
		const root = host.createElement("root");
		renderToHost(ul, host, root);
		const ulNode = (root as unknown as MockNode).children[0];
		assert listText(ulNode) === "7@08@1", "initial";
		setItems([8, 7]);
		assert listText(ulNode) === "8@07@1", "reordered rows keep live indexes";
		d();
	});
}

function mountedText(view: NeonNode): [() => string, () => void] {
	const host = mockHost();
	const root = host.createElement("root");
	let dispose: () => void = () => {};
	createRoot((d) => { dispose = d; renderToHost(view, host, root); });
	return [() => mockToString(root as unknown as MockNode), dispose];
}

test "a && <X/> child lowers to Show" {
	const [on, setOn] = createSignal(true);
	const [lowered, d1] = mountedText(element(<div>{on && <span>yes</span>}</div>));
	const [explicit, d2] = mountedText(element(<div><Show when={on()}><span>yes</span></Show></div>));
	assert lowered() === explicit(), "initial: lowered=" + lowered() + " explicit=" + explicit();
	assert lowered().indexOf("yes") >= 0, "child shown while true";
	setOn(false);
	assert lowered() === explicit(), "after off: lowered=" + lowered() + " explicit=" + explicit();
	assert lowered().indexOf("yes") < 0, "child gone while false";
	setOn(true);
	assert lowered() === explicit(), "after on: lowered=" + lowered() + " explicit=" + explicit();
	d1(); d2();
}

test "c ? <A/> : <B/> child lowers to Show with a fallback" {
	const [on, setOn] = createSignal(true);
	const [lowered, d1] = mountedText(element(<div>{on ? <span>yes</span> : <b>no</b>}</div>));
	const [explicit, d2] = mountedText(element(<div><Show when={on()} fallback={<b>no</b>}><span>yes</span></Show></div>));
	assert lowered() === explicit(), "initial: lowered=" + lowered() + " explicit=" + explicit();
	assert lowered().indexOf("yes") >= 0, "consequent shown while true";
	setOn(false);
	assert lowered() === explicit(), "after off: lowered=" + lowered() + " explicit=" + explicit();
	assert lowered().indexOf("no") >= 0, "alternate shown while false";
	d1(); d2();
}

test "a ternary with a null arm lowers to Show without a fallback, either way round" {
	const [on, setOn] = createSignal(true);
	const [nullElse, d1] = mountedText(element(<div>{on ? <span>yes</span> : null}</div>));
	const [nullThen, d2] = mountedText(element(<div>{on ? null : <span>yes</span>}</div>));
	const [explicit, d3] = mountedText(element(<div><Show when={on()}><span>yes</span></Show></div>));
	assert nullElse() === explicit(), "null-else initial: " + nullElse() + " vs " + explicit();
	assert nullThen().indexOf("yes") < 0, "null-then hides while true: " + nullThen();
	setOn(false);
	assert nullElse() === explicit(), "null-else after off: " + nullElse() + " vs " + explicit();
	assert nullThen().indexOf("yes") >= 0, "null-then shows while false: " + nullThen();
	d1(); d2(); d3();
}

test "xs.map(row) child lowers to For" {
	const [items, setItems] = createSignal<number[]>([1, 2, 3]);
	const [lowered, d1] = mountedText(element(<ul>{items.map((n: number): NeonNode => element(<li>{n.toString()}</li>))}</ul>));
	const [explicit, d2] = mountedText(element(<ul><For each={items()}>{(n: number, i: Accessor<number>): NeonNode => element(<li>{n.toString()}</li>)}</For></ul>));
	assert lowered() === explicit(), "initial: lowered=" + lowered() + " explicit=" + explicit();
	assert lowered().indexOf("3") >= 0, "rows rendered";
	setItems([3, 1, 2, 4]);
	assert lowered() === explicit(), "after reorder+append: lowered=" + lowered() + " explicit=" + explicit();
	setItems([]);
	assert lowered() === explicit(), "after clear: lowered=" + lowered() + " explicit=" + explicit();
	d1(); d2();
}

test "a lowered For row reads its index bare as an Accessor" {
	const [items, setItems] = createSignal<string[]>(["a", "b"]);
	const [lowered, d1] = mountedText(element(<ul>{items.map((s: string, i: Accessor<number>): NeonNode => element(<li>{s + i.toString()}</li>))}</ul>));
	assert lowered().indexOf("a0") >= 0 && lowered().indexOf("b1") >= 0, "indexed rows: " + lowered();
	setItems(["b", "a"]);
	assert lowered().indexOf("b0") >= 0 && lowered().indexOf("a1") >= 0, "indexes follow the reorder: " + lowered();
	d1();
}

test "Show mounts its branch untracked" {
	createRoot((d) => {
		const [on, setOn] = createSignal(true);
		const [n, setN] = createSignal(0);
		let builds = 0;
		const child: NeonNode = (h: Host, p: HostNode, b: HostNode | null): void => {
			builds = builds + 1;
			const label = n().toString();
			const built: NeonNode = <span>{label}</span>;
			built(h, p, b);
		};
		const div = el("div", [], [], [Show({ when: () => on(), children: child })]);
		const host = mockHost();
		const root = host.createElement("root");
		renderToHost(div, host, root);
		assert builds === 1, "branch built once on mount";
		setN(5);
		assert builds === 1, "a signal read while mounting does not rebuild the branch";
		setOn(false);
		setOn(true);
		assert builds === 2, "flipping the condition still rebuilds";
		d();
	});
}

test "Show mounts its fallback untracked" {
	createRoot((d) => {
		const [on, setOn] = createSignal(false);
		const [n, setN] = createSignal(0);
		let builds = 0;
		const fb: NeonNode = (h: Host, p: HostNode, b: HostNode | null): void => {
			builds = builds + 1;
			const label = n().toString();
			const built: NeonNode = <i>{label}</i>;
			built(h, p, b);
		};
		const div = el("div", [], [], [
			Show({ when: () => on(), children: <span>on</span>, fallback: fb }),
		]);
		const host = mockHost();
		const root = host.createElement("root");
		renderToHost(div, host, root);
		assert builds === 1, "fallback built once on mount";
		setN(5);
		assert builds === 1, "a signal read while mounting does not rebuild the fallback";
		setOn(true);
		setOn(false);
		assert builds === 2, "flipping the condition still rebuilds the fallback";
		d();
	});
}
