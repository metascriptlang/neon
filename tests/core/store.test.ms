import { createSignal, untrack } from "../../src/core/signal";
import { createEffect } from "../../src/core/effect";
import { createMemo } from "../../src/core/memo";
import { createRoot } from "../../src/core/owner";
import { flush } from "../../src/core/runtime";
import { Cleanup } from "../../src/core/types";
import { createStore } from "../../src/core/store";

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
