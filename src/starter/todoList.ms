// TodoList — the list component: <For> keyed rows, <Show> empty/done states, and
// state edits that replace the array rather than mutate it (value-keyed rows are
// reused by identity, so a fresh array is what drives the reconcile).
//
// Items are added from a preset ring, not typed: the Host contract's addEvent
// handler takes no event object, so no component can read an input's value yet.

import { createSignal } from "../core/signal";
import { createStyles, styleOf } from "../macros/ui/style";
import { NeonNode } from "../render/node";
import { NeonView } from "../render/host";
import { For, Show } from "../macros/ui/flow";

export interface Todo {
	id: int32;
	title: string;
	done: boolean;
}

const styles = createStyles({
	container: { flexDirection: "column", gap: 8, padding: 24, width: 320 },
	title: { color: "#cdd6f4", fontSize: 20, fontWeight: "bold" },
	row: { flexDirection: "row", alignItems: "center", gap: 8, padding: 8, backgroundColor: "#313244", borderRadius: 6 },
	label: { color: "#cdd6f4", fontSize: 14 },
	labelDone: { color: "#6c7086", fontSize: 14 },
	button: { backgroundColor: "#45475a", color: "#cdd6f4", padding: 6, borderRadius: 4, fontSize: 12 },
	empty: { color: "#6c7086", fontSize: 14, textAlign: "center", padding: 16 },
	banner: { color: "#a6e3a1", fontSize: 14, textAlign: "center" },
});

const presets = ["write a component", "wire the host", "ship the starter", "measure the mount"];

export function TodoList(): NeonNode {
	const [todos, setTodos] = createSignal<Todo[]>([
		{ id: 1, title: presets[0], done: false },
		{ id: 2, title: presets[1], done: true },
	]);
	let nextId = 3;

	const add = (): void => {
		const list = todos();
		const title = presets[nextId % presets.length];
		const next: Todo[] = [];
		for (const t of list) { next.push(t); }
		next.push({ id: nextId, title, done: false });
		nextId = nextId + 1;
		setTodos(next);
	};

	const toggle = (id: int32): void => {
		const next: Todo[] = [];
		for (const t of todos()) {
			if (t.id === id) { next.push({ id: t.id, title: t.title, done: !t.done }); }
			else { next.push(t); }
		}
		setTodos(next);
	};

	const remove = (id: int32): void => {
		const next: Todo[] = [];
		for (const t of todos()) {
			if (t.id !== id) { next.push(t); }
		}
		setTodos(next);
	};

	const allDone = (): boolean => {
		const list = todos();
		if (list.length === 0) { return false; }
		for (const t of list) {
			if (!t.done) { return false; }
		}
		return true;
	};

	return <div style={styles.container}>
		<div style={styles.title}>Todo</div>
		<button style={styles.button} onClick={() => add()}>add</button>
		<Show when={allDone()}>
			<div style={styles.banner}>all done</div>
		</Show>
		<Show when={todos().length === 0}>
			<div style={styles.empty}>nothing to do</div>
		</Show>
		<For each={todos()}>
			{(todo: Todo, i: () => int32): NeonView => <div style={styles.row}>
				<div style={todo.done ? styles.labelDone : styles.label}>{todo.title}</div>
				<button style={styles.button} onClick={() => toggle(todo.id)}>{todo.done ? "undo" : "done"}</button>
				<button style={styles.button} onClick={() => remove(todo.id)}>x</button>
			</div>}
		</For>
	</div>;
}
