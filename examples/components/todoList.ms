// TodoList — the list component: <For> keyed rows, <Show> empty/done states, and
// state edits that replace the array rather than mutate it (value-keyed rows are
// reused by identity, so a fresh array is what drives the reconcile).
//
// Items are added from a preset ring, not typed: TextInput's onChangeText works
// on the browser host today, and the starter keeps one vocabulary for every
// target — typed input joins when a native host carries it.

import { createSignal } from "../../src/core/signal";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { NeonNode } from "../../src/render/node";
import { NeonView } from "../../src/render/host";
import { For, Show } from "../../src/macros/ui/flow";
import { Accessor } from "../../src/core/signal";
import { View, Text, Pressable } from "../../src/components/primitives";

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

	return <View style={styles.container}>
		<Text style={styles.title}>Todo</Text>
		<Pressable style={styles.button} onPress={() => add()}>add</Pressable>
		<Show when={allDone()}>
			<Text style={styles.banner}>all done</Text>
		</Show>
		<Show when={todos().length === 0}>
			<Text style={styles.empty}>nothing to do</Text>
		</Show>
		<For each={todos()}>
			{(todo: Todo, i: Accessor<number>): NeonView => <View style={styles.row}>
				<Text style={todo.done ? styles.labelDone : styles.label}>{todo.title}</Text>
				<Pressable style={styles.button} onPress={() => toggle(todo.id)}>{todo.done ? "undo" : "done"}</Pressable>
				<Pressable style={styles.button} onPress={() => remove(todo.id)}>x</Pressable>
			</View>}
		</For>
	</View>;
}
