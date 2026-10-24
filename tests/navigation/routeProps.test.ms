import { sleepAsync } from "std/core/promise";
import { el, text, dynText, NeonNode } from "../../src/render/node";
import { HostNode, MockNode, mockNode, mockHost, render, mockToString } from "../../src/render/host";
import { element } from "../../src/macros/ui/element";
import { flush } from "../../src/core/runtime";
import { Loading } from "../../src/macros/ui/flow";
import { RoutingError } from "../../src/navigation/routing";
import { createMemoryRoutingHistory } from "../../src/navigation/routingHistory";
import {
	ParamsCodec,
	PreloadArgs,
	RouteSectionProps,
	componentOf,
	route,
} from "../../src/navigation/route";
import { Router, RouterProvider, createRoutes, createRouter } from "../../src/navigation/router";
import { query, createAsync } from "../../src/navigation/index";

interface Note {
	text: string;
}

const fetched: string[] = [];
let preloads: int32 = 0;

async function fetchNote(name: string): Promise<Note> {
	fetched.push(name);
	return { text: name };
}

struct NoteParams {
	id: string;
}

const noteCodec: ParamsCodec<NoteParams> = {
	parse: (values: Map<string, string>): Result<NoteParams, RoutingError> => {
		const id = values.get("id") ?? "";
		return id.length === 0 ? Result.err(RoutingError.InvalidParams) : Result.ok({ id });
	},
	stringify: (params: NoteParams): Map<string, string> => {
		const values = new Map<string, string>();
		values.set("id", params.id);
		return values;
	},
};

const getNote = query((id: string): Promise<Note> => fetchNote(id), "note");

const note = route<NoteParams, Promise<Note>>("/notes/:id", {
	params: noteCodec,
	preload: (args: PreloadArgs<NoteParams>): Promise<Note> => {
		preloads += 1;
		return getNote(args.params.id);
	},
});

const NotePage = componentOf<NoteParams, Promise<Note>>(note, (props: RouteSectionProps<NoteParams, Promise<Note>>): NeonNode => {
	const body = createAsync((): Promise<Note> => props.data);
	return Loading({
		children: el("p", [], [], dynText((): string => props.params.id + ":" + body().text + "@" + props.location.pathname)),
		fallback: el("b", [], [], text("loading")),
	});
});

function Plain(): NeonNode {
	return el("p", [], [], text("plain"));
}

function Seen(props: RouteSectionProps<Map<string, string>, unknown>): NeonNode {
	return el("p", [], [], text((props.params.get("slug") ?? "") + "@" + props.location.pathname));
}

function mounted(router: Router): MockNode {
	const root = mockNode("root");
	render(element(<RouterProvider router={router} />), mockHost(), root as unknown as HostNode);
	return root;
}

function opened(url: string): Router {
	const routes = createRoutes([
		{ route: note, component: NotePage },
		{ path: "/", component: Plain },
		{ path: "/docs/:slug", component: Seen },
	]);
	const made = createRouter(routes, createMemoryRoutingHistory({ url, state: "" }));
	if (!made.ok) { throw new Error("router: " + made.error.toString()); }
	return made.value;
}

test "a typed route's component reads the preload's promise as props.data, with its typed params, and the query fetches once" {
	const router = opened("/notes/7");
	const root = mounted(router);
	await sleepAsync(8);
	flush();
	assert mockToString(root).includes("<p>7:7@/notes/7</p>"), mockToString(root);
	assert fetched.length === 1, fetched.length.toString();
	assert preloads === 1, preloads.toString();
	router.dispose();
}

test "a component with no props still mounts, and a path entry's component gets the string params and the location" {
	const router = opened("/");
	const root = mounted(router);
	assert mockToString(root).includes("<p>plain</p>"), mockToString(root);
	assert router.navigate("/docs/start");
	flush();
	assert mockToString(root).includes("<p>start@/docs/start</p>"), mockToString(root);
	router.dispose();
}
