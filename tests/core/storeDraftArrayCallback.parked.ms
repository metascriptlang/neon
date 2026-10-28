import { createSignal } from "../../src/core/signal";
import { createRoot } from "../../src/core/owner";
import { flush } from "../../src/core/runtime";
import { createProjection, Draft } from "../../src/core/store";

interface Todo { id: number; title: string; done: boolean; }

test "a projection's draft array can be searched, overwritten and spliced" {
	const [todos, setTodos] = createSignal<Todo[]>([
		{ id: 1, title: "T1", done: false },
		{ id: 2, title: "T2", done: false },
		{ id: 3, title: "T3", done: false },
	]);
	const empty: Todo[] = [];
	const projection = createRoot((d) => {
		return createProjection<Todo[]>((draft) => {
			const all = todos();
			for (let i = 0; i < all.length; i += 1) {
				const todo = all[i];
				const index = draft.findIndex((existing: Draft<Todo>): boolean => existing.id === todo.id);
				const target = index === -1 ? draft.length : index;
				draft[target] = { id: todo.id, title: "", done: false };
				draft[target].title = todo.title;
				draft[target].done = todo.done;
			}
			for (let i = draft.length - 1; i >= 0; i -= 1) {
				const kept = all.findIndex((todo: Todo): boolean => todo.id === draft[i].id);
				if (kept === -1) { draft.splice(i, 1); }
			}
		}, empty);
	});
	assert projection.length === 3 && projection[0].title === "T1" && projection[2].id === 3, "first: " + projection.length.toString();
	setTodos(todos().filter((todo: Todo): boolean => todo.id !== 2));
	flush();
	assert projection.length === 2 && projection[0].id === 1 && projection[1].id === 3 && projection[1].title === "T3", "after: " + projection.length.toString();
	assert empty.length === 0, "the seed is never written";
}
