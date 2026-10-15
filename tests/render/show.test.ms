import { NeonNode } from "../../src/render/node";
import { MockNode, mockHost, render, mockToString } from "../../src/render/host";
import { createSignal, Accessor } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { renderToString } from "../../src/render/ssr";

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

// show.spec.tsx:11 "an only child show control flow"
test "a text-only child follows its condition" {
	const [count, setCount] = createSignal(0);
	const [read, d] = mounted(element(<div><Show when={count() >= 5}>{count().toString()}</Show></div>));
	assert read() === "<root><div></div></root>", "created: " + read();
	setCount(7);
	assert read() === "<root><div>7</div></root>", "seven: " + read();
	setCount(5);
	assert read() === "<root><div>5</div></root>", "five: " + read();
	setCount(2);
	assert read() === "<root><div></div></root>", "two: " + read();
	d();
}

// show.spec.tsx:90 "nonkeyed show control flow": when runs once per change, the child builds once per truthiness flip
test "a non-keyed element child builds on a truthiness flip, and when runs once per change" {
	const [count, setCount] = createSignal(0);
	let whenExecuted = 0;
	let childrenExecuted = 0;
	function when(): number { whenExecuted = whenExecuted + 1; return count(); }
	function built(): string { childrenExecuted = childrenExecuted + 1; return "b"; }
	const [read, d] = mounted(element(<div><Show when={when()}><span>{count().toString()}</span><span>{built()}</span></Show></div>));
	assert read() === "<root><div></div></root>", "created: " + read();
	assert whenExecuted === 1 && childrenExecuted === 0, "created counts " + whenExecuted.toString() + "/" + childrenExecuted.toString();
	setCount(7);
	assert whenExecuted === 2 && childrenExecuted === 1, "seven counts " + whenExecuted.toString() + "/" + childrenExecuted.toString();
	assert read() === "<root><div><span>7</span><span>b</span></div></root>", "seven: " + read();
	setCount(5);
	assert whenExecuted === 3 && childrenExecuted === 1, "five counts " + whenExecuted.toString() + "/" + childrenExecuted.toString();
	assert read() === "<root><div><span>5</span><span>b</span></div></root>", "five: " + read();
	setCount(5);
	assert whenExecuted === 3, "same value runs nothing";
	setCount(0);
	assert whenExecuted === 4 && childrenExecuted === 1, "zero counts " + whenExecuted.toString() + "/" + childrenExecuted.toString();
	assert read() === "<root><div></div></root>", "zero: " + read();
	setCount(5);
	assert whenExecuted === 5 && childrenExecuted === 2, "back counts " + whenExecuted.toString() + "/" + childrenExecuted.toString();
	d();
}

// show.spec.tsx:140 "keyed show control flow": a new value rebuilds the child
test "a keyed element child rebuilds on each new value, and when runs once per change" {
	const [count, setCount] = createSignal(0);
	let whenExecuted = 0;
	let childrenExecuted = 0;
	function when(): number { whenExecuted = whenExecuted + 1; return count(); }
	function built(): string { childrenExecuted = childrenExecuted + 1; return "b"; }
	const [read, d] = mounted(element(<div><Show when={when()} keyed><span>{count().toString()}</span><span>{built()}</span></Show></div>));
	assert whenExecuted === 1 && childrenExecuted === 0, "created counts " + whenExecuted.toString() + "/" + childrenExecuted.toString();
	setCount(7);
	assert whenExecuted === 2 && childrenExecuted === 1, "seven counts " + whenExecuted.toString() + "/" + childrenExecuted.toString();
	setCount(5);
	assert whenExecuted === 3 && childrenExecuted === 2, "five rebuilt " + whenExecuted.toString() + "/" + childrenExecuted.toString();
	assert read() === "<root><div><span>5</span><span>b</span></div></root>", "five: " + read();
	setCount(5);
	assert whenExecuted === 3, "same value runs nothing";
	setCount(0);
	assert whenExecuted === 4 && childrenExecuted === 2, "zero counts " + whenExecuted.toString() + "/" + childrenExecuted.toString();
	assert read() === "<root><div></div></root>", "zero: " + read();
	setCount(5);
	assert whenExecuted === 5 && childrenExecuted === 3, "back counts " + whenExecuted.toString() + "/" + childrenExecuted.toString();
	d();
}

// show.spec.tsx:200 "nonkeyed function show control flow": the narrowed accessor follows the value without a rebuild
test "a non-keyed function child gets an accessor that follows the value, and when runs once per change" {
	const [count, setCount] = createSignal(0);
	let whenExecuted = 0;
	let childrenExecuted = 0;
	function when(): number { whenExecuted = whenExecuted + 1; return count(); }
	function built(): string { childrenExecuted = childrenExecuted + 1; return "b"; }
	const [read, d] = mounted(element(<div><Show when={when()}>{(c: Accessor<number>): NeonNode => <><span>{c().toString()}</span><span>{built()}</span></>}</Show></div>));
	assert read() === "<root><div></div></root>", "created: " + read();
	assert whenExecuted === 1 && childrenExecuted === 0, "created counts " + whenExecuted.toString() + "/" + childrenExecuted.toString();
	setCount(7);
	assert whenExecuted === 2 && childrenExecuted === 1, "seven counts " + whenExecuted.toString() + "/" + childrenExecuted.toString();
	assert read() === "<root><div><span>7</span><span>b</span></div></root>", "seven: " + read();
	setCount(5);
	assert whenExecuted === 3 && childrenExecuted === 1, "five counts " + whenExecuted.toString() + "/" + childrenExecuted.toString();
	assert read() === "<root><div><span>5</span><span>b</span></div></root>", "five: " + read();
	setCount(5);
	assert whenExecuted === 3, "same value runs nothing";
	setCount(0);
	assert whenExecuted === 4 && childrenExecuted === 1, "zero counts " + whenExecuted.toString() + "/" + childrenExecuted.toString();
	assert read() === "<root><div></div></root>", "zero: " + read();
	setCount(5);
	assert whenExecuted === 5 && childrenExecuted === 2, "back counts " + whenExecuted.toString() + "/" + childrenExecuted.toString();
	d();
}

// flow.ts:176 the keyed condition is the value memo itself: a value that recomputes to the same one rebuilds nothing
test "a keyed child does not rebuild when the value recomputes to the same one" {
	const [count, setCount] = createSignal(7);
	let elementBuilt = 0;
	let functionBuilt = 0;
	function elementCount(): string { elementBuilt = elementBuilt + 1; return "e"; }
	function functionCount(): string { functionBuilt = functionBuilt + 1; return "f"; }
	const [read, d] = mounted(element(<div>
		<Show when={count() >= 5} keyed><span>{elementCount()}</span></Show>
		<Show when={count() >= 5} keyed>{(on: boolean): NeonNode => <b>{functionCount()}</b>}</Show>
	</div>));
	assert elementBuilt === 1 && functionBuilt === 1, "built at mount";
	setCount(8);
	assert elementBuilt === 1 && functionBuilt === 1, "8 is still true: " + elementBuilt.toString() + "/" + functionBuilt.toString();
	setCount(2);
	setCount(9);
	assert elementBuilt === 2 && functionBuilt === 2, "a flip rebuilds: " + elementBuilt.toString() + "/" + functionBuilt.toString();
	d();
}

// show.spec.tsx:252 "keyed function show control flow": the function receives the value and runs again for each new one
test "a keyed function child gets the value and runs for each new one" {
	const [count, setCount] = createSignal(0);
	let executed = 0;
	function built(): string { executed = executed + 1; return "b"; }
	const [read, d] = mounted(element(<div><Show when={count()} keyed>{(c: number): NeonNode => <><span>{c.toString()}</span><span>{built()}</span></>}</Show></div>));
	assert read() === "<root><div></div></root>" && executed === 0, "created: " + read();
	setCount(7);
	assert read() === "<root><div><span>7</span><span>b</span></div></root>" && executed === 1, "seven: " + read();
	setCount(5);
	assert read() === "<root><div><span>5</span><span>b</span></div></root>" && executed === 2, "five: " + read();
	setCount(0);
	assert read() === "<root><div></div></root>" && executed === 2, "zero: " + read();
	d();
}

// show.spec.tsx:299 "keyed function" over an object: every new object rebuilds, the type is the object
test "a keyed function child over a nullable object receives the object" {
	const [user, setUser] = createSignal<User | null>(null);
	let executed = 0;
	const [read, d] = mounted(element(<div><Show when={user()} keyed>{(u: User): NeonNode => { executed = executed + 1; return <span>{u.name}</span>; }}</Show></div>));
	assert read() === "<root><div></div></root>", "created: " + read();
	setUser(new User("ann"));
	assert read() === "<root><div><span>ann</span></div></root>" && executed === 1, "ann: " + read();
	setUser(new User("ann"));
	assert read() === "<root><div><span>ann</span></div></root>" && executed === 2, "a new object with the same name rebuilds: " + executed.toString();
	setUser(null);
	assert read() === "<root><div></div></root>" && executed === 2, "null: " + read();
	d();
}

// show.spec.tsx:343 "non-keyed function" over an object: the accessor follows the value, the child is not rebuilt
test "a non-keyed function child over a nullable object follows the value without a rebuild" {
	const [user, setUser] = createSignal<User | null>(null);
	let executed = 0;
	const [read, d] = mounted(element(<div><Show when={user()}>{(u: Accessor<User>): NeonNode => { executed = executed + 1; return <span>{u().name}</span>; }}</Show></div>));
	assert read() === "<root><div></div></root>", "created: " + read();
	setUser(new User("ann"));
	assert read() === "<root><div><span>ann</span></div></root>" && executed === 1, "ann: " + read();
	setUser(new User("bob"));
	assert read() === "<root><div><span>bob</span></div></root>" && executed === 1, "bob follows in place: " + read() + " built " + executed.toString();
	setUser(null);
	assert read() === "<root><div></div></root>", "null: " + read();
	setUser(new User("cy"));
	assert read() === "<root><div><span>cy</span></div></root>" && executed === 2, "cy rebuilds after a hide: " + read();
	d();
}

// show.spec.tsx:392 "DOM children and fallback"
test "a fallback shows while the condition is off, in every child form" {
	const [count, setCount] = createSignal(0);
	const [user, setUser] = createSignal<User | null>(null);
	const [element1, d1] = mounted(element(<div><Show when={count() >= 5} fallback={<i>low</i>}><span>{count().toString()}</span></Show></div>));
	const [keyedEl, d2] = mounted(element(<div><Show when={count() >= 5} keyed fallback={<i>low</i>}><span>{count().toString()}</span></Show></div>));
	const [withFn, d3] = mounted(element(<div><Show when={user()} fallback={<i>none</i>}>{(u: Accessor<User>): NeonNode => <span>{u().name}</span>}</Show></div>));
	const [keyedFn, d4] = mounted(element(<div><Show when={user()} keyed fallback={<i>none</i>}>{(u: User): NeonNode => <span>{u.name}</span>}</Show></div>));
	assert element1() === "<root><div><i>low</i></div></root>", "element off: " + element1();
	assert keyedEl() === "<root><div><i>low</i></div></root>", "keyed element off: " + keyedEl();
	assert withFn() === "<root><div><i>none</i></div></root>", "function off: " + withFn();
	assert keyedFn() === "<root><div><i>none</i></div></root>", "keyed function off: " + keyedFn();
	setCount(7);
	setUser(new User("ann"));
	assert element1() === "<root><div><span>7</span></div></root>", "element on: " + element1();
	assert keyedEl() === "<root><div><span>7</span></div></root>", "keyed element on: " + keyedEl();
	assert withFn() === "<root><div><span>ann</span></div></root>", "function on: " + withFn();
	assert keyedFn() === "<root><div><span>ann</span></div></root>", "keyed function on: " + keyedFn();
	setCount(2);
	setUser(null);
	assert element1() === "<root><div><i>low</i></div></root>", "element off again: " + element1();
	assert keyedEl() === "<root><div><i>low</i></div></root>", "keyed element off again: " + keyedEl();
	assert withFn() === "<root><div><i>none</i></div></root>", "function off again: " + withFn();
	assert keyedFn() === "<root><div><i>none</i></div></root>", "keyed function off again: " + keyedFn();
	d1(); d2(); d3(); d4();
}

// flow.ts:239 narrowedError("Show"): the accessor is valid only while the condition holds
test "the narrowed accessor throws when read after the condition went false" {
	const [user, setUser] = createSignal<User | null>(new User("ann"));
	let held: Accessor<User> | null = null;
	const [read, d] = mounted(element(<div><Show when={user()}>{(u: Accessor<User>): NeonNode => { held = u; return <span>{u().name}</span>; }}</Show></div>));
	const live = held as Accessor<User>;
	assert live().name === "ann", "reads while on";
	setUser(null);
	let caught = "";
	try {
		live();
	} catch (e) {
		caught = e.toString();
	}
	assert caught.includes("narrowed value was read while its condition is false"), "names the misuse: " + caught;
	d();
}

// flow.ts:176 the when memo is owned by the Show: disposing the view stops it
test "disposing the view stops the when expression" {
	const [count, setCount] = createSignal(1);
	let whenExecuted = 0;
	function when(): number { whenExecuted = whenExecuted + 1; return count(); }
	const [read, d] = mounted(element(<div><Show when={when()}>{(c: Accessor<number>): NeonNode => <span>{c().toString()}</span>}</Show></div>));
	assert whenExecuted === 1, "ran once at mount";
	d();
	setCount(2);
	assert whenExecuted === 1, "never again after dispose: " + whenExecuted.toString();
}

// a bare Accessor reads by calling it, like the boolean one
test "a bare accessor of a nullable object is the when value" {
	const [user, setUser] = createSignal<User | null>(null);
	const [read, d] = mounted(element(<div><Show when={user}>{(u: Accessor<User>): NeonNode => <span>{u().name}</span>}</Show></div>));
	assert read() === "<root><div></div></root>", "created: " + read();
	setUser(new User("ann"));
	assert read() === "<root><div><span>ann</span></div></root>", "ann: " + read();
	d();
}

test "a function child without a parameter type gets the narrowed type" {
	const [user, setUser] = createSignal<User | null>(null);
	const [read, d] = mounted(element(<div><Show when={user()}>{(u): NeonNode => <b>{u().name}</b>}</Show></div>));
	setUser(new User("ann"));
	assert read() === "<root><div><b>ann</b></div></root>", "ann: " + read();
	d();
}

test "a Show nests inside a function child" {
	const [user, setUser] = createSignal<User | null>(null);
	const [age, setAge] = createSignal<number | null>(null);
	const [read, d] = mounted(element(<div><Show when={user()}>{(u: Accessor<User>): NeonNode => <p>{u().name}<Show when={age()}>{(a: Accessor<number>): NeonNode => <b>{a().toString()}</b>}</Show></p>}</Show></div>));
	setUser(new User("ann"));
	assert read() === "<root><div><p>ann</p></div></root>", "outer only: " + read();
	setAge(9);
	assert read() === "<root><div><p>ann<b>9</b></p></div></root>", "inner on: " + read();
	setUser(null);
	assert read() === "<root><div></div></root>", "outer off: " + read();
	d();
}

test "the function forms render to a string" {
	const [user, setUser] = createSignal<User | null>(new User("ann"));
	const html = renderToString(element(<div>
		<Show when={user()}>{(u: Accessor<User>): NeonNode => <b>{u().name}</b>}</Show>
		<Show when={user()} keyed>{(u: User): NeonNode => <i>{u.name}</i>}</Show>
		<Show when={user()} keyed fallback={<u>none</u>}><s>kept</s></Show>
	</div>));
	assert html === "<div><b>ann</b><!----><i>ann</i><!----><s>kept</s><!----></div>", html;
}
