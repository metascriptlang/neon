import { domHost, documentBody } from "../../src/platform/browser/dom";
import { Counter } from "./counter";
import { Tally } from "./sibling";

function App(): NeonNode {
	return <section>
		<Counter label="clicks" />
		<Tally name="tally" />
		<textarea id="notes"></textarea>
	</section>;
}

render(App(), domHost(), documentBody());
