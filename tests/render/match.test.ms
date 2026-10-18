import { NeonNode } from "../../src/render/node";
import { MockNode, mockHost, render, mockToString } from "../../src/render/host";
import { createSignal, untrack, Accessor } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { flush } from "../../src/core/runtime";

class User {
	name: string;
	constructor(name: string) { this.name = name; }
}

function mounted(view: NeonNode): [() => string, () => void] {
	const host = mockHost();
	const root = host.createElement("root");
	const dispose = render(view, host, root);
	return [() => mockToString(root as unknown as MockNode), dispose];
}

test "the first case whose when is truthy wins, and a later truthy case is ignored" {
	const [n, setN] = createSignal(1);
	const [read, d] = mounted(element(<div><Match fallback={<i>none</i>}>
		<Case when={n() === 1}><b>one</b></Case>
		<Case when={n() >= 1}><b>many</b></Case>
		<Case when={n() >= 1}><b>also many</b></Case>
	</Match></div>));
	assert read() === "<root><div><b>one</b></div></root>", "one: " + read();
	setN(3);
	flush();
	assert read() === "<root><div><b>many</b></div></root>", "three is the second, not the third: " + read();
	setN(0);
	flush();
	assert read() === "<root><div><i>none</i></div></root>", "none: " + read();
	d();
}

test "a case behind a winner does not evaluate its when, and is evaluated again once the winner stops matching" {
	const [list, setList] = createSignal<number[]>([]);
	let reads = 0;
	function first(): number { reads = reads + 1; return list()[0]; }
	const [read, d] = mounted(element(<div><Match>
		<Case when={list().length === 0}><b>empty</b></Case>
		<Case when={first() > 5}><b>big</b></Case>
	</Match></div>));
	assert read() === "<root><div><b>empty</b></div></root>" && reads === 0, "empty reads nothing: " + reads.toString();
	setList([9]);
	flush();
	assert read() === "<root><div><b>big</b></div></root>" && reads === 1, "big: " + read() + " reads " + reads.toString();
	setList([1]);
	flush();
	assert read() === "<root><div></div></root>" && reads === 2, "small matches nothing: " + read();
	setList([]);
	flush();
	assert read() === "<root><div><b>empty</b></div></root>" && reads === 2, "empty again reads nothing: " + reads.toString();
	setList([3, 4]);
	flush();
	assert read() === "<root><div></div></root>" && reads === 3, "a changed list reads again: " + reads.toString();
	d();
}

test "a branch keeps its nodes while its own case stays selected, and mounts again when the index changes" {
	const [n, setN] = createSignal(2);
	let built = 0;
	function tag(): string { built = built + 1; return "x"; }
	const host = mockHost();
	const root = host.createElement("root");
	const d = render(element(<div><Match>
		<Case when={n() === 1}><b>one</b></Case>
		<Case when={n() >= 2}><span>{tag()}{n().toString()}</span></Case>
	</Match></div>), host, root);
	const box = (root as unknown as MockNode).children[0];
	const span = box.children[0];
	assert mockToString(root as unknown as MockNode) === "<root><div><span>x2</span></div></root>", "two: " + mockToString(root as unknown as MockNode);
	setN(3);
	flush();
	assert box.children[0] === span && built === 1, "the same node while the index stays: " + built.toString();
	assert mockToString(root as unknown as MockNode) === "<root><div><span>x3</span></div></root>", "text follows in place";
	setN(1);
	flush();
	assert mockToString(root as unknown as MockNode) === "<root><div><b>one</b></div></root>", "one";
	setN(4);
	flush();
	assert box.children[0] !== span && built === 2, "a new node after the index changed: " + built.toString();
	d();
}

test "a branch keeps its own state across changes inside the same case" {
	const [n, setN] = createSignal(2);
	let hold: (() => void) | null = null;
	function counter(): NeonNode {
		const [c, setC] = createSignal(0);
		hold = (): void => { setC(c() + 1); };
		return <u>{c().toString()}</u>;
	}
	const [read, d] = mounted(element(<div><Match>
		<Case when={n() === 1}><b>one</b></Case>
		<Case when={n() >= 2}>{counter()}</Case>
	</Match></div>));
	(hold as () => void)();
	flush();
	(hold as () => void)();
	flush();
	assert read() === "<root><div><u>2</u></div></root>", "two bumps: " + read();
	setN(9);
	flush();
	assert read() === "<root><div><u>2</u></div></root>", "kept through a change inside the case: " + read();
	d();
}

test "a keyed case mounts again for each new value, and a non-keyed callback follows the value in place" {
	const [user, setUser] = createSignal<User | null>(null);
	let keyedBuilt = 0;
	let plainBuilt = 0;
	const [keyed, d1] = mounted(element(<div><Match fallback={<i>none</i>}>
		<Case when={user()} keyed>{(u: User): NeonNode => { keyedBuilt = keyedBuilt + 1; return <span>{u.name}</span>; }}</Case>
	</Match></div>));
	const [plain, d2] = mounted(element(<div><Match fallback={<i>none</i>}>
		<Case when={user()}>{(u: Accessor<User>): NeonNode => { plainBuilt = plainBuilt + 1; return <span>{u().name}</span>; }}</Case>
	</Match></div>));
	assert keyed() === "<root><div><i>none</i></div></root>" && plain() === "<root><div><i>none</i></div></root>", "fallback first";
	setUser(new User("ann"));
	flush();
	assert keyed() === "<root><div><span>ann</span></div></root>" && keyedBuilt === 1, "keyed ann: " + keyed();
	assert plain() === "<root><div><span>ann</span></div></root>" && plainBuilt === 1, "plain ann: " + plain();
	setUser(new User("bob"));
	flush();
	assert keyed() === "<root><div><span>bob</span></div></root>" && keyedBuilt === 2, "a new identity mounts again: " + keyedBuilt.toString();
	assert plain() === "<root><div><span>bob</span></div></root>" && plainBuilt === 1, "the accessor follows in place: " + plainBuilt.toString();
	setUser(null);
	flush();
	assert keyed() === "<root><div><i>none</i></div></root>" && plain() === "<root><div><i>none</i></div></root>", "fallback again";
	d1(); d2();
}

test "keyed without a callback, and the plain form over a nullable value" {
	const [user, setUser] = createSignal<User | null>(null);
	let keyedBuilt = 0;
	function tag(): string { keyedBuilt = keyedBuilt + 1; return "k"; }
	const [read, d] = mounted(element(<div><Match>
		<Case when={user()} keyed><s>{tag()}</s></Case>
	</Match></div>));
	assert read() === "<root><div></div></root>", "null";
	setUser(new User("ann"));
	flush();
	setUser(new User("bob"));
	flush();
	assert read() === "<root><div><s>k</s></div></root>" && keyedBuilt === 2, "keyed element mounts per value: " + keyedBuilt.toString();
	d();
}

test "the callback receives the narrowed value on a case behind another, and a read after its case left throws" {
	const [a, setA] = createSignal<User | null>(null);
	const [b, setB] = createSignal<User | null>(new User("bea"));
	let held: Accessor<User> | null = null;
	const [read, d] = mounted(element(<div><Match fallback={<i>none</i>}>
		<Case when={a()}>{(u: Accessor<User>): NeonNode => <b>{u().name}</b>}</Case>
		<Case when={b()}>{(u: Accessor<User>): NeonNode => { held = u; return <span>{u().name}</span>; }}</Case>
	</Match></div>));
	assert read() === "<root><div><span>bea</span></div></root>", "bea: " + read();
	setB(new User("bo"));
	flush();
	assert read() === "<root><div><span>bo</span></div></root>", "bo: " + read();
	setA(new User("ann"));
	flush();
	assert read() === "<root><div><b>ann</b></div></root>", "the earlier case wins: " + read();
	let thrown = "";
	try { untrack((): User => (held as Accessor<User>)()); } catch (e) { thrown = (e as Error).message; }
	assert thrown.indexOf("<Case>: the narrowed value was read while its case is not selected") === 0, "a stale read throws: " + thrown;
	d();
}

test "an empty Match renders its fallback, or nothing" {
	const [read, d] = mounted(element(<div><Match fallback={<i>none</i>}></Match><Match></Match></div>));
	assert read() === "<root><div><i>none</i></div></root>", "empty: " + read();
	d();
}

test "a value case behind a winner does not read its source" {
	const [list, setList] = createSignal<User[]>([]);
	let reads = 0;
	function head(): User | null { reads = reads + 1; return list().length > 0 ? list()[0] : null; }
	const [read, d] = mounted(element(<div><Match>
		<Case when={list().length === 0}><b>empty</b></Case>
		<Case when={head()}>{(u: Accessor<User>): NeonNode => <i>{u().name}</i>}</Case>
	</Match></div>));
	assert read() === "<root><div><b>empty</b></div></root>" && reads === 0, "empty: " + reads.toString();
	setList([new User("ann")]);
	flush();
	assert read() === "<root><div><i>ann</i></div></root>" && reads === 1, "ann: " + read() + reads.toString();
	setList([]);
	flush();
	assert read() === "<root><div><b>empty</b></div></root>" && reads === 1, "empty again: " + reads.toString();
	d();
}
