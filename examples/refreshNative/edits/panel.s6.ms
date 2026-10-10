import { Counter, Tally } from "./counter";

export function Panel(): NeonNode {
	return <section>
		<h1>Panel v2</h1>
		<Counter label="a" />
		<Tally name="b" />
	</section>;
}
