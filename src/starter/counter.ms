// Counter — the canonical first Neon component: own state, bare JSX, no macro call.
// Handlers receive a typed NeonEvent since 2026-09-03 (src/render/event.ms) — inputs
// reading e.value are writable now; this file predates the RN surface (onPress) rename.

import { createSignal } from "../core/signal";
import { createStyles, styleOf } from "../macros/ui/style";
import { NeonNode } from "../render/node";

const styles = createStyles({
	container: { flexDirection: "column", alignItems: "center", gap: 12, padding: 24 },
	title: { color: "#cdd6f4", fontSize: 20, fontWeight: "bold" },
	value: { color: "#89b4fa", fontSize: 48, fontWeight: "bold" },
	row: { flexDirection: "row", gap: 12 },
	button: { backgroundColor: "#313244", color: "#cdd6f4", padding: 12, borderRadius: 8, fontSize: 16 },
	hint: { color: "#6c7086", fontSize: 12 },
});

export function Counter(): NeonNode {
	const [count, setCount] = createSignal(0);
	return <div style={styles.container}>
		<div style={styles.title}>Neon Counter</div>
		<div style={styles.value}>{count().toString()}</div>
		<div style={styles.row}>
			<button style={styles.button} onClick={() => setCount(count() - 1)}>-</button>
			<button style={styles.button} onClick={() => setCount(0)}>reset</button>
			<button style={styles.button} onClick={() => setCount(count() + 1)}>+</button>
		</div>
		<div style={styles.hint}>{count() % 2 === 0 ? "even" : "odd"}</div>
	</div>;
}
