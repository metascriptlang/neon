import { Counter, Tally } from "./counter";

export function Panel(): NeonNode {
	return <section>
		<h1>Panel v1</h1>
		<Counter label="a" />
		<Tally name="b" />
	</section>;
}
