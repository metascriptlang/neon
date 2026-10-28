import { el, text, dynText, NeonNode } from "../../src/render/node";
import { mockHost, mockNode, mockToString, MockNode, Host, HostNode, render } from "../../src/render/host";
import { hydrate } from "../../src/render/hydrate";
import { putRecord, putError, clearRecords } from "../../src/render/hydrationRecords";
import { Accessor } from "../../src/core/signal";
import { query, createAsync, queryKey } from "../../src/navigation/index";

interface User {
	name: string;
	n: int32;
}

const runs = [0];

async function loadUser(id: string): Promise<User> {
	runs[0] = runs[0] + 1;
	return { name: "live-" + id, n: 1 };
}

function served(tree: NeonNode): MockNode {
	const root = mockNode("root");
	const dispose = render(tree, mockHost(), root as unknown as HostNode, "");
	dispose();
	root.events = [];
	return root;
}

function line(read: () => string): NeonNode {
	return el("p", [], [], dynText(read));
}

test "a query whose key has a record adopts it with no call of the function, once" {
	clearRecords();
	runs[0] = 0;
	const getUser = query(loadUser, "hyd");
	putRecord(queryKey("hyd", "1"), JSON.stringify<User>({ name: "srv-1", n: 7 }));
	const root = served(line((): string => "srv-1"));
	const before = mockToString(root);
	let read: Accessor<User> | null = null;
	const page: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		read = createAsync((): Promise<User> => getUser("1"));
		line((): string => "srv-1")(host, parent, before);
	};
	const dispose = hydrate(page, mockHost(), root as unknown as HostNode);
	try {
		await sleepAsync(8);
		assert mockToString(root) === before, mockToString(root);
		assert (read as Accessor<User>)().name === "srv-1", "the memo settled on the record";
		assert runs[0] === 0, "the record answered: " + runs[0].toString();
		await getUser("1");
		assert runs[0] === 0, "the adopted answer is the cached one: " + runs[0].toString();
	} finally {
		dispose();
		clearRecords();
	}
}

test "a query whose key has an error record rejects with it and does not run the function" {
	clearRecords();
	runs[0] = 0;
	const getUser = query(loadUser, "hydErr");
	putError(queryKey("hydErr", "1"), "boom");
	let caught = "";
	const page: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		getUser("1").then((u: User): void => {}, (e: Error): void => { caught = e.message; });
	};
	const root = mockNode("root");
	const dispose = hydrate(page, mockHost(), root as unknown as HostNode);
	await sleepAsync(8);
	dispose();
	clearRecords();
	assert caught === "boom", caught;
	assert runs[0] === 0, runs[0].toString();
}
