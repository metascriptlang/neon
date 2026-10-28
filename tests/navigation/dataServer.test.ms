import { sleepAsync } from "std/core/promise";
import { el, text, dynText, NeonNode } from "../../src/render/node";
import { Host, HostNode } from "../../src/render/hostTypes";
import { Loading } from "../../src/macros/ui/flow";
import { renderToStream } from "../../src/render/ssr";
import { element } from "../../src/macros/ui/element";
import { createRequestRoutingHistory } from "../../src/navigation/routingHistory";
import { redirect } from "../../src/navigation/route";
import { RouterProvider, createRouter, createRoutes } from "../../src/navigation/router";
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

async function signedOut(): Promise<User> {
	throw redirect("/login");
}

const getSigned = query(signedOut, "srvSigned");

function Account(): NeonNode {
	const user = createAsync((): Promise<User> => getSigned());
	return Loading({ children: el("p", [], [], dynText((): string => user().name)), fallback: waiting });
}

test "a query that throws a redirect during a server render becomes the router's response" {
	const routes = createRoutes([{ path: "/account", component: Account }]);
	const opened = createRouter(routes, createRequestRoutingHistory("/account"));
	assert opened.ok;
	if (opened.ok) {
		const router = opened.value;
		let failed = "";
		try { await renderToStream(<RouterProvider router={router} />); } catch (error) { failed = error.message; }
		const response = router.response();
		assert response.status === 307 && response.location === "/login", response.status.toString() + " " + (response.location ?? "-") + " " + failed;
		router.dispose();
	}
}
