import { createSignal, untrack } from "../../src/core/signal";
import { createEffect } from "../../src/core/effect";
import { createMemo } from "../../src/core/memo";
import { createRoot } from "../../src/core/owner";
import { flush } from "../../src/core/runtime";
import { Cleanup } from "../../src/core/types";
import { createStore, snapshot, reconcile } from "../../src/core/store";

interface Todo { id: number; title: string; done: boolean; }
interface Item { id: number; title: string; }
interface User { firstName: string; lastName: string; }

test "a setStore write batches: reads return the previous value until flush" {
	const [state, setState] = createStore({ key: "" });
	setState((s) => { s.key = "value"; });
	assert state.key === "", "before flush: " + state.key;
	flush();
	assert state.key === "value", "after flush: " + state.key;
}

test "array writes batch: an element write, a push and a shift show only after flush" {
	const [todos, setTodos] = createStore<Todo[]>([
		{ id: 1, title: "Go To Work", done: true },
		{ id: 2, title: "Eat Lunch", done: false },
	]);
	setTodos((t) => { t[1].done = true; });
	setTodos((t) => { t.push({ id: 3, title: "Go Home", done: false }); });
	setTodos((t) => { t.shift(); });
	assert todos.length === 2 && todos[0].done && todos[1].title === "Eat Lunch", "pre-write array";
	flush();
	assert todos.length === 2 && todos[0].title === "Eat Lunch" && todos[0].done && todos[1].title === "Go Home", "after flush";
}

test "a nested array write batches with its parent" {
	const [state, setState] = createStore<{ todos: Todo[] }>({ todos: [
		{ id: 1, title: "Go To Work", done: true },
		{ id: 2, title: "Eat Lunch", done: false },
	] });
	setState((s) => { s.todos[1].done = true; });
	setState((s) => { s.todos.push({ id: 3, title: "Go Home", done: false }); });
	assert !state.todos[1].done && state.todos.length === 2, "pre-write";
	flush();
	assert state.todos[1].done && state.todos.length === 3 && state.todos[2].title === "Go Home", "after flush";
}

test "an effect re-runs on a store change, and not on a write of the same value" {
	const [state, setState] = createStore({ data: 2 });
	const seen: number[] = [];
	createRoot((d) => {
		createEffect<number>((p: number | null): number => state.data, (v: number, p: number | null): Cleanup | null => { seen.push(v); return null; });
	});
	flush();
	setState((s) => { s.data = 5; });
	flush();
	setState((s) => { s.data = 5; });
	flush();
	assert seen.join(",") === "2,5", "runs: " + seen.join(",");
}

test "a nested write re-runs only the readers of that field" {
	const [state, setState] = createStore<{ user: User }>({ user: { firstName: "John", lastName: "Smith" } });
	const first: string[] = [];
	const last: string[] = [];
	createRoot((d) => {
		createEffect<string>((p: string | null): string => state.user.firstName, (v: string, p: string | null): Cleanup | null => { first.push(v); return null; });
		createEffect<string>((p: string | null): string => state.user.lastName, (v: string, p: string | null): Cleanup | null => { last.push(v); return null; });
	});
	flush();
	setState((s) => { s.user.firstName = "Jake"; });
	flush();
	assert first.join(",") === "John,Jake" && last.join(",") === "Smith", "first " + first.join(",") + " last " + last.join(",");
}

test "a pop re-runs the reader of the removed element and of the length" {
	const [state, setState] = createStore<number[]>([1]);
	const seen: number[] = [];
	createRoot((d) => {
		createEffect<number>((p: number | null): number => state.length > 0 ? state[0] : -1, (v: number, p: number | null): Cleanup | null => { seen.push(v); return null; });
	});
	flush();
	setState((s) => { s.pop(); });
	flush();
	assert seen.join(",") === "1,-1", "runs: " + seen.join(",");
}

test "iteration over a store array re-runs on an add, an update and a truncation" {
	const [state, setState] = createStore<string[]>(["hi"]);
	const byIndex: string[] = [];
	const byOf: string[] = [];
	createRoot((d) => {
		createEffect<string>((p: string | null): string => {
			let all = "";
			for (let i = 0; i < state.length; i += 1) { all += state[i] + ";"; }
			return all;
		}, (v: string, p: string | null): Cleanup | null => { byIndex.push(v); return null; });
		createEffect<string>((p: string | null): string => {
			let all = "";
			for (const item of state) { all += item + ";"; }
			return all;
		}, (v: string, p: string | null): Cleanup | null => { byOf.push(v); return null; });
	});
	flush();
	setState((s) => { s[1] = "item"; });
	flush();
	setState((s) => { s[1] = "new"; });
	flush();
	setState((s) => { s.length = 1; });
	flush();
	const want = "hi;|hi;item;|hi;new;|hi;";
	assert byIndex.join("|") === want, "by index: " + byIndex.join("|");
	assert byOf.join("|") === want, "by for-of: " + byOf.join("|");
}

test "a truncation re-runs the reader of a cut index" {
	const [state, setState] = createStore<number[]>([1, 2, 3]);
	let runs = 0;
	createRoot((d) => {
		createEffect<number>((p: number | null): number => state.length > 2 ? state[2] : -1, (v: number, p: number | null): Cleanup | null => { runs += 1; return null; });
	});
	flush();
	setState((s) => { s.length = 1; });
	flush();
	assert runs === 2 && state.length === 1, "runs: " + runs.toString();
}

test "a read past the committed end of a store array is an error" {
	const [state, setState] = createStore<number[]>([1]);
	setState((s) => { s.push(2); });
	let message = "";
	try { const v = state[1]; } catch (e) { message = (e as Error).message; }
	assert message === "index 1 is past the end of a store array of length 1", "message: " + message;
	flush();
	assert state[1] === 2;
}

test "a memo over a store array method re-runs on a write" {
	const [state, setState] = createStore<{ list: number[] }>({ list: [0, 1, 2] });
	let filtered: () => number[] = () => [];
	createRoot((d) => {
		filtered = createMemo<number[]>((): number[] => state.list.filter((i: number): boolean => i % 2 === 1));
	});
	assert filtered().join(",") === "1";
	setState((s) => { s.list.push(3); });
	flush();
	assert filtered().join(",") === "1,3", "filtered: " + filtered().join(",");
}

test "an effect's apply may write a store" {
	const [data, setData] = createSignal("init");
	const [state, setState] = createStore({ data: "" });
	createRoot((d) => {
		createEffect<string>((p: string | null): string => data(), (v: string, p: string | null): Cleanup | null => {
			setState((s) => { s.data = v; });
			return null;
		});
	});
	setData("signal");
	flush();
	assert state.data === "signal", "data: " + state.data;
}

test "a store object read twice is the same nested store, and a replaced object is a new one" {
	const [state, setState] = createStore<{ user: User }>({ user: { firstName: "John", lastName: "Smith" } });
	const names: string[] = [];
	createRoot((d) => {
		createEffect<string>((p: string | null): string => state.user.firstName, (v: string, p: string | null): Cleanup | null => { names.push(v); return null; });
	});
	flush();
	setState((s) => { s.user = { firstName: "Ann", lastName: "Lee" }; });
	flush();
	setState((s) => { s.user.firstName = "Bo"; });
	flush();
	assert names.join(",") === "John,Ann,Bo", "names: " + names.join(",");
}

test "an untracked read of a field that has no reader sees the committed value" {
	const [state, setState] = createStore({ a: 1, b: 1 });
	setState((s) => { s.a = 2; });
	assert untrack<number>((): number => state.a) === 1;
	flush();
	assert state.a === 2;
}

test "a row held across a shift re-runs its reader when edited at its new index" {
	const [todos, setItems] = createStore<Item[]>([{ id: 1, title: "a" }, { id: 2, title: "b" }]);
	const row = todos[1];
	const seen: string[] = [];
	createRoot((d) => {
		createEffect<string>((p: string | null): string => row.title, (v: string, p: string | null): Cleanup | null => { seen.push(v); return null; });
	});
	flush();
	setItems((t) => { t.shift(); });
	flush();
	setItems((t) => { t[0].title = "B"; });
	flush();
	assert seen.join(",") === "b,B", "seen: " + seen.join(",");
}

test "one object under two keys is one store: a write through one re-runs the reader of the other" {
	const shared: Item = { id: 1, title: "a" };
	const [state, setState] = createStore<{ x: Item, y: Item }>({ x: shared, y: shared });
	const seen: string[] = [];
	createRoot((d) => {
		createEffect<string>((p: string | null): string => state.y.title, (v: string, p: string | null): Cleanup | null => { seen.push(v); return null; });
	});
	flush();
	setState((s) => { s.x.title = "b"; });
	flush();
	assert seen.join(",") === "a,b", "seen: " + seen.join(",");
}

test "the seed object passed to createStore is never written" {
	const seed = { a: 1, b: 2 };
	const [state, setState] = createStore(seed);
	setState((s) => { s.a = 10; });
	flush();
	assert state.a === 10, "store: " + state.a.toString();
	assert seed.a === 1, "seed: " + seed.a.toString();
}

test "a nested seed object and a seed array are never written" {
	const user: User = { firstName: "John", lastName: "Smith" };
	const rows: Item[] = [{ id: 1, title: "a" }, { id: 2, title: "b" }];
	const [state, setState] = createStore<{ user: User, rows: Item[] }>({ user, rows });
	setState((s) => { s.user.firstName = "Jake"; });
	setState((s) => { s.rows[0].title = "A"; });
	setState((s) => { s.rows.push({ id: 3, title: "c" }); });
	setState((s) => { s.rows.shift(); });
	flush();
	assert state.user.firstName === "Jake" && state.rows.length === 2 && state.rows[0].title === "b" && state.rows[1].id === 3, "store";
	assert user.firstName === "John", "seed user: " + user.firstName;
	assert rows.length === 2 && rows[0].title === "a" && rows[0].id === 1, "seed rows: " + rows.length.toString() + " " + rows[0].title;
}

test "an object written into a store is not written by a later edit through the store" {
	const [state, setState] = createStore<{ user: User }>({ user: { firstName: "John", lastName: "Smith" } });
	const fresh: User = { firstName: "Ann", lastName: "Lee" };
	setState((s) => { s.user = fresh; });
	flush();
	setState((s) => { s.user.firstName = "Bo"; });
	flush();
	assert state.user.firstName === "Bo", "store: " + state.user.firstName;
	assert fresh.firstName === "Ann", "fresh: " + fresh.firstName;
}

test "an edit under a privatized parent still reaches the reader of a sibling edit" {
	const user: User = { firstName: "John", lastName: "Smith" };
	const [state, setState] = createStore<{ user: User, n: number }>({ user, n: 1 });
	const seen: string[] = [];
	createRoot((d) => {
		createEffect<string>((p: string | null): string => state.user.firstName + state.n.toString(), (v: string, p: string | null): Cleanup | null => { seen.push(v); return null; });
	});
	flush();
	setState((s) => { s.n = 2; });
	flush();
	setState((s) => { s.user.firstName = "Jake"; });
	flush();
	assert seen.join(",") === "John1,John2,Jake2", "seen: " + seen.join(",");
	assert user.firstName === "John";
}

interface Doc { id: number; user: User; tags: string[]; rows: Item[]; }

function newDoc(): Doc {
	return { id: 1, user: { firstName: "John", lastName: "Smith" }, tags: ["a"], rows: [{ id: 1, title: "x" }] };
}

test "snapshot of an unwritten store is its seed, subtree by subtree" {
	const seed = newDoc();
	const [state, setState] = createStore<Doc>(seed);
	assert snapshot(state) === seed, "root";
	const user = state.user;
	assert snapshot(user) === seed.user, "user";
	setState((s) => { s.user.firstName = "Jake"; });
	flush();
	const snap = snapshot(state);
	assert snap !== seed, "a written root is a copy";
	assert snap.user.firstName === "Jake" && snap.id === 1 && snap.tags.length === 1, "copied values";
	assert snap.tags === seed.tags && snap.rows === seed.rows, "an untouched subtree is the seed's own";
}

test "snapshot is plain data detached from the store" {
	const [state, setState] = createStore<Doc>(newDoc());
	setState((s) => { s.rows[0].title = "y"; });
	setState((s) => { s.rows.push({ id: 2, title: "z" }); });
	flush();
	const snap = snapshot(state);
	setState((s) => { s.rows[0].title = "later"; });
	setState((s) => { s.rows.shift(); });
	setState((s) => { s.user.lastName = "Doe"; });
	flush();
	assert snap.rows.length === 2 && snap.rows[0].title === "y" && snap.rows[1].title === "z", "rows: " + snap.rows.length.toString();
	assert snap.user.lastName === "Smith", "user: " + snap.user.lastName;
	assert state.rows.length === 1 && state.rows[0].title === "z" && state.user.lastName === "Doe", "store moved on";
}

test "snapshot sees the batch's pending writes before the flush" {
	const [state, setState] = createStore<Doc>(newDoc());
	setState((s) => { s.user.firstName = "Jake"; s.tags.push("b"); });
	assert state.user.firstName === "John" && state.tags.length === 1, "store reads stay committed";
	const snap = snapshot(state);
	assert snap.user.firstName === "Jake" && snap.tags.length === 2 && snap.tags[1] === "b", "snapshot: " + snap.user.firstName;
	flush();
}

test "snapshot of a nested store reads the subtree and tracks only the read of that field" {
	const [state, setState] = createStore<Doc>(newDoc());
	const seen: string[] = [];
	createRoot((d) => {
		createEffect<User>((p: User | null): User => { const user = state.user; return snapshot(user); }, (v: User, p: User | null): Cleanup | null => { seen.push(v.firstName); return null; });
	});
	flush();
	setState((s) => { s.user.firstName = "Jake"; });
	flush();
	setState((s) => { s.user = { firstName: "Ann", lastName: "Lee" }; });
	flush();
	assert seen.join(",") === "John,Ann", "seen: " + seen.join(",");
}

test "a row held across a shift is copied at its new index, and the array keeps its length" {
	const seed: Item[] = [{ id: 1, title: "a" }, { id: 2, title: "b" }];
	const [todos, setItems] = createStore<Item[]>(seed);
	const row = todos[1];
	setItems((t) => { t.shift(); });
	flush();
	setItems((t) => { t[0].title = "B"; });
	flush();
	assert todos.length === 1, "length: " + todos.length.toString();
	assert todos[0].title === "B" && row.title === "B", "title: " + todos[0].title;
	const snap = snapshot(todos);
	assert snap.length === 1 && snap[0].title === "B", "backing length: " + snap.length.toString();
	assert seed.length === 2 && seed[0].title === "a" && seed[1].title === "b", "seed";
}

interface Row { id: number; name: string; count: number; }
interface Pair { data: number; label: string; }
interface Board { title: string; owner: User; rows: Row[]; }

const JOHN: Row = { id: 1, name: "John", count: 1 };
const NED: Row = { id: 2, name: "Ned", count: 2 };
const BRANDON: Row = { id: 3, name: "Brandon", count: 3 };
const ARYA: Row = { id: 4, name: "Arya", count: 4 };

function ids(rows: Row[]): string {
	let all = "";
	for (let i = 0; i < rows.length; i += 1) { all += rows[i].id.toString() + ","; }
	return all;
}

test "reconcile merges an object: only a changed field re-runs its readers" {
	const [state, setState] = createStore<Pair>({ data: 2, label: "a" });
	const data: number[] = [];
	const label: string[] = [];
	createRoot((d) => {
		createEffect<number>((p: number | null): number => state.data, (v: number, p: number | null): Cleanup | null => { data.push(v); return null; });
		createEffect<string>((p: string | null): string => state.label, (v: string, p: string | null): Cleanup | null => { label.push(v); return null; });
	});
	flush();
	setState(reconcile<Pair>({ data: 5, label: "a" }, null));
	flush();
	assert data.join(",") === "2,5" && label.join(",") === "a", "data " + data.join(",") + " label " + label.join(",");
	assert state.data === 5 && state.label === "a";
}

test "reconcile at a nested path merges into that record" {
	const [state, setState] = createStore<Board>({ title: "t", owner: { firstName: "John", lastName: "Snow" }, rows: [] });
	let runs = 0;
	createRoot((d) => {
		createEffect<string>((p: string | null): string => { runs += 1; return state.owner.lastName; }, (v: string, p: string | null): Cleanup | null => null);
	});
	flush();
	setState((s) => { reconcile<User>({ firstName: "Jake", lastName: "Snow" }, null)(s.owner); });
	flush();
	assert state.owner.firstName === "Jake" && state.owner.lastName === "Snow", "owner";
	assert runs === 1, "the unchanged field's reader ran " + runs.toString() + " times";
}

test "reconcile reorders a keyed array and keeps the rows themselves" {
	const [state, setState] = createStore<{ users: Row[] }>({ users: [JOHN, NED, BRANDON] });
	setState((s) => { reconcile<Row[]>([NED, JOHN, BRANDON], "id")(s.users); });
	flush();
	let users = snapshot(state).users;
	assert users[0] === NED && users[1] === JOHN && users[2] === BRANDON, "swap: " + ids(users);
	setState((s) => { reconcile<Row[]>([NED, BRANDON, JOHN, ARYA], "id")(s.users); });
	flush();
	users = snapshot(state).users;
	assert users.length === 4 && users[1] === BRANDON && users[2] === JOHN && users[3] === ARYA, "add: " + ids(users);
	setState((s) => { reconcile<Row[]>([BRANDON, JOHN, ARYA], "id")(s.users); });
	flush();
	users = snapshot(state).users;
	assert users.length === 3 && users[0] === BRANDON && users[1] === JOHN && users[2] === ARYA, "remove: " + ids(users);
	assert JOHN.name === "John" && JOHN.count === 1, "the incoming rows are never written";
}

test "a keyed row matched by id keeps its readers: only a changed field re-runs" {
	const [state, setState] = createStore<Row[]>([{ id: 1, name: "a", count: 1 }, { id: 2, name: "b", count: 2 }]);
	const name0: string[] = [];
	const count0: number[] = [];
	const count1: number[] = [];
	createRoot((d) => {
		createEffect<string>((p: string | null): string => state[0].name, (v: string, p: string | null): Cleanup | null => { name0.push(v); return null; });
		createEffect<number>((p: number | null): number => state[0].count, (v: number, p: number | null): Cleanup | null => { count0.push(v); return null; });
		createEffect<number>((p: number | null): number => state[1].count, (v: number, p: number | null): Cleanup | null => { count1.push(v); return null; });
	});
	flush();
	setState(reconcile<Row[]>([{ id: 1, name: "a", count: 10 }, { id: 2, name: "b", count: 2 }], "id"));
	flush();
	assert name0.join(",") === "a", "name0: " + name0.join(",");
	assert count0.join(",") === "1,10", "count0: " + count0.join(",");
	assert count1.join(",") === "2", "count1: " + count1.join(",");
}

test "a held row follows its id through a keyed reorder" {
	const [state, setState] = createStore<Row[]>([{ id: 1, name: "a", count: 1 }, { id: 2, name: "b", count: 2 }]);
	const row = state[1];
	const seen: string[] = [];
	createRoot((d) => {
		createEffect<string>((p: string | null): string => row.name, (v: string, p: string | null): Cleanup | null => { seen.push(v); return null; });
	});
	flush();
	setState(reconcile<Row[]>([{ id: 2, name: "B", count: 2 }, { id: 1, name: "a", count: 1 }], "id"));
	flush();
	assert row.name === "B" && state[0].name === "B" && state[1].name === "a", "names";
	assert seen.join(",") === "b,B", "seen: " + seen.join(",");
}

test "a keyed reconcile that drops and adds rows notifies the length and the cut index" {
	const [state, setState] = createStore<Row[]>([{ id: 1, name: "a", count: 1 }, { id: 2, name: "b", count: 2 }, { id: 3, name: "c", count: 3 }]);
	const lengths: number[] = [];
	let tail = "";
	createRoot((d) => {
		createEffect<number>((p: number | null): number => state.length, (v: number, p: number | null): Cleanup | null => { lengths.push(v); return null; });
		createEffect<string>((p: string | null): string => state.length > 2 ? state[2].name : "none", (v: string, p: string | null): Cleanup | null => { tail = v; return null; });
	});
	flush();
	setState(reconcile<Row[]>([{ id: 1, name: "a", count: 1 }], "id"));
	flush();
	assert state.length === 1 && lengths.join(",") === "3,1" && tail === "none", "shrink: " + lengths.join(",") + " " + tail;
	setState(reconcile<Row[]>([{ id: 1, name: "a", count: 1 }, { id: 5, name: "e", count: 5 }, { id: 6, name: "f", count: 6 }], "id"));
	flush();
	assert state.length === 3 && lengths.join(",") === "3,1,3" && tail === "f" && state[1].name === "e", "grow: " + lengths.join(",") + " " + tail;
}

test "a positional reconcile merges index by index into the rows already there" {
	const [state, setState] = createStore<{ rows: Row[] }>({ rows: [{ id: 7, name: "x", count: 1 }, { id: 8, name: "y", count: 2 }] });
	const row0 = state.rows[0];
	const seen: number[] = [];
	createRoot((d) => {
		createEffect<number>((p: number | null): number => row0.count, (v: number, p: number | null): Cleanup | null => { seen.push(v); return null; });
	});
	flush();
	setState((s) => { reconcile<Row[]>([{ id: 7, name: "x", count: 11 }, { id: 9, name: "z", count: 21 }], null)(s.rows); });
	flush();
	assert row0.count === 11 && state.rows[0].count === 11, "row0";
	assert state.rows[1].id === 9 && state.rows[1].name === "z" && state.rows[1].count === 21, "row1";
	assert seen.join(",") === "1,11", "seen: " + seen.join(",");
}

test "a reconcile of a primitive array rewrites it in place" {
	const [state, setState] = createStore<string[]>(["a", "b", "c"]);
	let last = "";
	createRoot((d) => {
		createEffect<string>((p: string | null): string => state.length > 1 ? state[1] : "none", (v: string, p: string | null): Cleanup | null => { last = v; return null; });
	});
	flush();
	setState(reconcile<string[]>(["a"], null));
	flush();
	assert state.length === 1 && last === "none", "shrink: " + last;
	setState(reconcile<string[]>(["z", "y"], null));
	flush();
	assert state.length === 2 && state[0] === "z" && last === "y", "grow: " + last;
}

test "reconcile refuses another entity at the root, by key" {
	const [user, setUser] = createStore<Row>({ id: 1, name: "John", count: 1 });
	let message = "";
	try { setUser(reconcile<Row>({ id: 2, name: "Ned", count: 2 }, "id")); } catch (e) { message = (e as Error).message; }
	assert message === "Cannot reconcile states with different identity", "message: " + message;
	flush();
	assert user.id === 1 && user.name === "John", "the store is untouched";
	setUser(reconcile<Row>({ id: 1, name: "Jon", count: 1 }, "id"));
	flush();
	assert user.name === "Jon", "the same entity merges";
}

test "reconcile refuses another entity at a nested path" {
	const [state, setState] = createStore<{ owner: Row }>({ owner: { id: 1, name: "John", count: 1 } });
	let message = "";
	try { setState((s) => { reconcile<Row>({ id: 2, name: "Ned", count: 2 }, "id")(s.owner); }); } catch (e) { message = (e as Error).message; }
	assert message === "Cannot reconcile states with different identity", "message: " + message;
}

test "reconcile writes neither the seed nor the incoming data" {
	const seedRows: Row[] = [{ id: 1, name: "a", count: 1 }, { id: 2, name: "b", count: 2 }];
	const incoming: Row[] = [{ id: 2, name: "B", count: 20 }, { id: 3, name: "c", count: 3 }];
	const [state, setState] = createStore<Row[]>(seedRows);
	setState(reconcile<Row[]>(incoming, "id"));
	flush();
	setState((s) => { s[0].count = 99; s[1].count = 98; });
	flush();
	assert state[0].count === 99 && state[1].count === 98 && state[0].name === "B", "store";
	assert seedRows[0].name === "a" && seedRows[1].name === "b" && seedRows[1].count === 2 && seedRows.length === 2, "seed";
	assert incoming[0].count === 20 && incoming[1].count === 3 && incoming.length === 2, "incoming";
}

test "reconcile descends into a nested record: an unchanged leaf's reader does not re-run" {
	const [state, setState] = createStore<Board>({ title: "t", owner: { firstName: "John", lastName: "Snow" }, rows: [{ id: 1, name: "a", count: 1 }] });
	let runs = 0;
	let rowRuns = 0;
	createRoot((d) => {
		createEffect<string>((p: string | null): string => { runs += 1; return state.owner.lastName; }, (v: string, p: string | null): Cleanup | null => null);
		createEffect<string>((p: string | null): string => { rowRuns += 1; return state.rows[0].name; }, (v: string, p: string | null): Cleanup | null => null);
	});
	flush();
	setState(reconcile<Board>({ title: "t2", owner: { firstName: "Jake", lastName: "Snow" }, rows: [{ id: 1, name: "a", count: 2 }] }, "id"));
	flush();
	assert state.title === "t2" && state.owner.firstName === "Jake" && state.rows[0].count === 2, "merged";
	assert runs === 1, "owner.lastName ran " + runs.toString() + " times";
	assert rowRuns === 1, "rows[0].name ran " + rowRuns.toString() + " times";
}

interface Pair2 { first: string; second: string; }
interface Count { count: number; label: string; }

test "a derived store holds its derive's first value at once and re-derives when a source changes" {
	const [source, setSource] = createSignal(1);
	let calls = 0;
	const [state, setState] = createRoot((d) => {
		return createStore<Count>((draft) => { calls += 1; draft.count = source(); draft.label = "n"; }, { count: 0, label: "" });
	});
	assert state.count === 1 && state.label === "n" && calls === 1, "first value: " + state.count.toString();
	const counts: number[] = [];
	let labelRuns = 0;
	createRoot((d) => {
		createEffect<number>((p: number | null): number => state.count, (v: number, p: number | null): Cleanup | null => { counts.push(v); return null; });
		createEffect<string>((p: string | null): string => { labelRuns += 1; return state.label; }, (v: string, p: string | null): Cleanup | null => null);
	});
	flush();
	setSource(2);
	flush();
	assert state.count === 2 && calls === 2, "second value: " + state.count.toString();
	assert counts.join(",") === "1,2", "counts: " + counts.join(",");
	assert labelRuns === 1, "the unchanged key's reader ran " + labelRuns.toString() + " times";
}

test "a derive does not track the reads it makes through its own draft" {
	const [bar, setBar] = createSignal("foo");
	let calls = 0;
	const [state, setState] = createRoot((d) => {
		return createStore<Pair2>((draft) => { calls += 1; draft.first = draft.second; draft.second = bar(); }, { first: "foo", second: "bar" });
	});
	assert state.first === "bar" && state.second === "foo" && calls === 1, "first";
	setBar("baz");
	flush();
	assert state.first === "foo" && state.second === "baz" && calls === 2, "second: " + state.first + " " + state.second;
}

test "a memo that runs in the flush of a source change reads the re-derived value, never the old one" {
	const [source, setSource] = createSignal(1);
	const [other, setOther] = createSignal(0);
	const [state, setState] = createRoot((d) => {
		return createStore<Count>((draft) => { draft.count = source() * 10; }, { count: 0, label: "" });
	});
	const seen: number[] = [];
	let total: () => number = () => 0;
	createRoot((d) => {
		total = createMemo<number>((): number => { const v = other() * 100 + state.count; seen.push(v); return v; });
	});
	assert total() === 10;
	setOther(1);
	setSource(2);
	flush();
	assert total() === 120, "total: " + total().toString();
	assert seen.join(",") === "10,120", "runs: " + seen.join(",");
}

test "a write through a derived store's setter lasts until the next derive, which wins" {
	const [source, setSource] = createSignal(0);
	const [state, setState] = createRoot((d) => {
		return createStore<Count>((draft) => { draft.count = source(); }, { count: -1, label: "" });
	});
	flush();
	assert state.count === 0;
	setSource(1);
	setState((s) => { s.count = 99; });
	flush();
	assert state.count === 1, "the derive wins in its own flush: " + state.count.toString();
	setState((s) => { s.count = 99; });
	flush();
	assert state.count === 99, "the manual write stands: " + state.count.toString();
	setSource(2);
	flush();
	assert state.count === 2, "the next derive: " + state.count.toString();
}

test "a derived store stops deriving when its owner is disposed" {
	const [source, setSource] = createSignal(1);
	let calls = 0;
	let release: () => void = () => {};
	const [state, setState] = createRoot((d) => {
		release = d;
		return createStore<Count>((draft) => { calls += 1; draft.count = source(); }, { count: 0, label: "" });
	});
	assert calls === 1;
	release();
	setSource(2);
	flush();
	assert calls === 1, "calls: " + calls.toString();
}

test "the seed of a derived store is never written" {
	const seed: Count = { count: 0, label: "s" };
	const [source, setSource] = createSignal(3);
	const [state, setState] = createRoot((d) => {
		return createStore<Count>((draft) => { draft.count = source(); }, seed);
	});
	setSource(4);
	flush();
	assert state.count === 4 && seed.count === 0, "seed: " + seed.count.toString();
}

test "a splice through the draft removes the rows and re-runs the readers of the moved indexes" {
	const [items, setItems] = createStore<number[]>([1, 2, 3, 4]);
	const seen: string[] = [];
	createRoot((d) => {
		createEffect<number>((p: number | null): number => items[1], (v: number, p: number | null): Cleanup | null => { seen.push(v.toString()); return null; });
	});
	flush();
	setItems((t) => { t.splice(1, 2); });
	flush();
	assert items.length === 2 && items[0] === 1 && items[1] === 4, "items: " + items.length.toString();
	assert seen.join(",") === "2,4", "seen: " + seen.join(",");
}
