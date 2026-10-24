import { sleepAsync } from "std/core/promise";
import { el, text, dynText, NeonNode } from "../../src/render/node";
import { Host, HostNode } from "../../src/render/hostTypes";
import { Loading } from "../../src/macros/ui/flow";
import { renderToStream } from "../../src/render/ssr";
import { query, createAsync } from "../../src/navigation/index";

interface User {
	name: string;
	n: int32;
}

const runs = [0];

async function loadUser(id: string): Promise<User> {
	runs[0] = runs[0] + 1;
	await sleepAsync(5);
	return { name: "user-" + id, n: 7 };
}

const waiting: NeonNode = el("b", [], [], text("loading"));

test "renderToStream writes the query's record under its key, and fetches once across the passes" {
	const getUser = query(loadUser, "srv");
	const page = (): NeonNode => (host: Host, parent: HostNode, before: HostNode | null): void => {
		const user = createAsync((): Promise<User> => getUser("1"));
		el("p", [], [], dynText((): string => user().name))(host, parent, before);
	};
	const out = await renderToStream(Loading({ children: page(), fallback: waiting }));
	assert out.html === "<p>user-1</p><!---->", out.html;
	const record = "r[\"srv[\\\"1\\\"]\"]=\"{\\\"name\\\":\\\"user-1\\\",\\\"n\\\":7}\"";
	assert out.records.includes(record), "the query key carries the answer: " + out.records;
	assert runs[0] === 1, "one fetch: " + runs[0].toString();
}
