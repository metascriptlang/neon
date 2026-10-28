import { sleepAsync } from "std/core/promise";
import { Accessor, createSignal, untrack } from "../../src/core/signal";
import { flush } from "../../src/core/runtime";
import { NeonNode } from "../../src/render/hostTypes";
import { el, text } from "../../src/render/node";
import { element } from "../../src/macros/ui/element";
import { HostNode, mockNode, mockHost, render, mockToString } from "../../src/render/host";
import { Errored, Loading, Show } from "../../src/macros/ui/flow";
import { createMemoryRoutingHistory } from "../../src/navigation/routingHistory";
import { Router, RouterProvider, createRouter, createRoutes } from "../../src/navigation/router";
import { query, createAsync } from "../../src/navigation/index";

enum Read {
	Untracked,
	UntrackedUnderShow,
	InJsx,
}

interface Page {
	score: int32;
}

const LOOP_STOP: int32 = 3;
const fetches = [0];
const bodies = [0];
const round = [0];
const mode = [Read.Untracked];

async function readPage(n: int32): Promise<Page> {
	fetches[0] = fetches[0] + 1;
	await sleepAsync(3);
	return { score: 7 };
}

const pageOf = query(readPage, "untrackedPage");

function Vote(props: { score: Accessor<int32> }): NeonNode {
	bodies[0] = bodies[0] + 1;
	if (mode[0] === Read.InJsx) { return <p>{String(props.score())}</p>; }
	if (bodies[0] > LOOP_STOP) { throw new Error("looped"); }
	const [score, setScore] = createSignal<int32>(untrack((): int32 => props.score()));
	return <p>{String(score())}</p>;
}

function Body(): NeonNode {
	const page = createAsync((): Promise<Page> => pageOf(round[0]));
	if (mode[0] === Read.UntrackedUnderShow) {
		return <Show when={page().score >= 0}><Vote score={page().score} /></Show>;
	}
	return <Vote score={page().score} />;
}

function Thread(): NeonNode {
	return <Errored fallback={(failure: Accessor<Error>, reset: () => void): NeonNode => <i>{failure().message}</i>}>
		<Loading fallback={<b>loading</b>}>
			<Body />
		</Loading>
	</Errored>;
}

function Home(): NeonNode {
	return el("p", [], [], text("home"));
}

function opened(): Router {
	const made = createRouter(createRoutes([
		{ path: "/", component: Home },
		{ path: "/t", component: Thread },
	]), createMemoryRoutingHistory({ url: "/", state: "" }));
	if (!made.ok) { throw new Error("router: " + made.error.toString()); }
	return made.value;
}

async function navigatedWith(read: Read): Promise<string> {
	mode[0] = read;
	round[0] = round[0] + 1;
	fetches[0] = 0;
	bodies[0] = 0;
	const router = opened();
	const root = mockNode("root");
	const dispose = render(element(<RouterProvider router={router} />), mockHost(), root as unknown as HostNode);
	flush();
	if (!router.navigate("/t")) { throw new Error("navigate refused"); }
	for (let i = 0; i < 30 && bodies[0] <= LOOP_STOP && !mockToString(root).includes("<p>"); i += 1) {
		await sleepAsync(2);
		flush();
	}
	const shown = mockToString(root);
	dispose();
	router.dispose();
	return shown;
}

test "a navigation into a page that reads its pending query in JSX fetches once and renders" {
	const shown = await navigatedWith(Read.InJsx);
	assert fetches[0] === 1 && bodies[0] === 1, "fetches " + fetches[0].toString() + ", bodies " + bodies[0].toString();
	assert shown.includes("<p>7</p>"), shown;
}

test "a navigation into a page whose untracked read waits under Show fetches once and renders" {
	const shown = await navigatedWith(Read.UntrackedUnderShow);
	assert fetches[0] === 1 && bodies[0] === 1, "fetches " + fetches[0].toString() + ", bodies " + bodies[0].toString();
	assert shown.includes("<p>7</p>"), shown;
}

test "an untracked pending read in a body under Loading re-runs the content each time it settles, as Solid 2.0 does" {
	const shown = await navigatedWith(Read.Untracked);
	assert bodies[0] === LOOP_STOP + 1, "the read links the content pass above its scope: bodies " + bodies[0].toString();
	assert fetches[0] === 1, "each new createAsync hits the query entry: fetches " + fetches[0].toString();
	assert shown.includes("<i>looped</i>"), shown;
}
