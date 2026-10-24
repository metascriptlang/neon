import { createStore, snapshot } from "../../src/core/store";

interface User { firstName: string; lastName: string; }
interface Doc { id: number; user: User; }

test "snapshot of a nested store read in the argument infers the record type" {
	const [state, setState] = createStore<Doc>({ id: 1, user: { firstName: "a", lastName: "b" } });
	const user = snapshot(state.user);
	assert user.firstName === "a";
}
