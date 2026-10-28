import { View, Text } from "../../src/components/primitives";
import { Head } from "../../src/render/head";
import { NeonNode } from "../../src/render/hostTypes";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { GuardDecision, RouteMatch, redirect } from "../../src/navigation/route";
import { Routes, createRoutes } from "../../src/navigation/router";
import { App, DocumentProps, RequestEvent, getRequestEvent, serve } from "../../src/render/serve";
import { renderToString } from "../../src/render/ssr";
import { publishWindow, useWindowDimensions } from "../../src/render/environment";
import { createRoot } from "../../src/core/owner";
import { Dispose } from "../../src/core/types";
import { createAsyncMemo } from "../../src/core/memo";
import { Gate, gated, release } from "../core/asyncClock";

const looks = createStyles({ page: { padding: 7 } });

function Home(): NeonNode {
	return <View style={looks.page}><Head><title>Served home</title></Head><Text>home body</Text></View>;
}

function Gone(): NeonNode {
	return <Text>this page is gone</Text>;
}

function Missing(): NeonNode {
	return <View><Head><title>Missing</title></Head><Text>no such page</Text></View>;
}

function widthFor(event: RequestEvent | null): string {
	if (event === null) { return "no request"; }
	const agent = event.request.headers.get("user-agent");
	const width = agent !== null && agent.includes("Mobi") ? "390" : "1440";
	return "width " + width + " for " + event.request.url;
}

function Width(): NeonNode {
	return <Text>{widthFor(getRequestEvent())}</Text>;
}

function Tag(): NeonNode {
	const event = getRequestEvent();
	const tag = event === null ? null : event.request.headers.get("X-Tag");
	return <Text>{"tag " + (tag === null ? "none" : tag)}</Text>;
}

let laterGate = new Gate();
let laterStarted: int32 = 0;

function Later(): NeonNode {
	laterStarted += 1;
	const ready = createAsyncMemo((p: string | null): Promise<string> => gated(laterGate, "ready"));
	return <Text>{ready() + " " + widthFor(getRequestEvent())}</Text>;
}

let sizedGate = new Gate();

function Sized(): NeonNode {
	const agentName = getRequestEvent()?.request.headers.get("user-agent") ?? "";
	publishWindow(agentName.includes("Mobi") ? 390 : 1440, 800);
	const size = useWindowDimensions();
	const ready = createAsyncMemo((p: string | null): Promise<string> => gated(sizedGate, "sized"));
	return <Text>{ready() + " " + size().width.toString() + "x" + size().height.toString()}</Text>;
}

const moduleSize = useWindowDimensions();

function SizedAtModule(): NeonNode {
	publishWindow(390, 800);
	return <Text>{moduleSize().width.toString()}</Text>;
}

function agent(value: string): Map<string, string> {
	const headers = new Map<string, string>();
	headers.set("User-Agent", value);
	return headers;
}

function moved(params: Map<string, string>, found: RouteMatch): GuardDecision {
	return redirect("/");
}

const routes: Routes = createRoutes([
	{ path: "/", component: Home },
	{ path: "/old", component: Gone, guard: moved },
	{ path: "/gone", status: 410, component: Gone },
	{ path: "/width", component: Width },
	{ path: "/later", component: Later },
	{ path: "/tag", component: Tag },
	{ path: "/sized", component: Sized },
	{ path: "/sizedAtModule", component: SizedAtModule },
]);

const app: App = { routes: routes, notFound: <Text>app not found</Text>, client: "/client.js", document: null };

test "a matched route is a 200 document with head, css, body and client script placed" {
	const served = await serve(app, "/");
	assert served.status === 200 && served.location === null, served.status.toString();
	const body = served.body;
	assert body.startsWith("<!doctype html><html><head><meta charset=\"utf-8\"><title data-neon-head=\"\">Served home</title><style>"), body;
	const root = body.indexOf("</style></head><body><div id=\"app\">");
	assert root > 0 && body.indexOf("home body") > root, body;
	assert body.indexOf("</div>", root) > body.indexOf("home body"), body;
	assert body.endsWith("<script type=\"module\" src=\"/client.js\"></script></body></html>"), body;
}

function SiteDocument(props: DocumentProps): NeonNode {
	const assets = props.assets;
	const scripts = props.scripts;
	const children = props.children;
	return <html lang="en"><head><meta charset="utf-8" /><link rel="icon" href="/favicon.ico" />{assets}</head><body><main id="site">{children}</main>{scripts}</body></html>;
}

test "a document component places the page, and the head content lands before its </head>" {
	const served = await serve({ routes: routes, notFound: <Text>app not found</Text>, client: "/site.js", document: SiteDocument }, "/");
	const body = served.body;
	assert body.startsWith("<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><link rel=\"icon\" href=\"/favicon.ico\"><title data-neon-head=\"\">Served home</title><style>"), body;
	const root = body.indexOf("</style></head><body><main id=\"site\">");
	assert root > 0 && body.indexOf("home body") > root, body;
	assert body.endsWith("</main><script type=\"module\" src=\"/site.js\"></script></body></html>"), body;
}

function LocaleDocument(props: DocumentProps): NeonNode {
	const event = getRequestEvent();
	const language = event === null ? null : event.request.headers.get("accept-language");
	const children = props.children;
	return <html lang={language === null ? "none" : language}><head></head><body>{children}</body></html>;
}

test "the document renders inside the request, so it reads the request event" {
	const headers = new Map<string, string>();
	headers.set("Accept-Language", "vi");
	const served = await serve({ routes: routes, notFound: <Text>app not found</Text>, client: "", document: LocaleDocument }, "/", headers);
	assert served.body.startsWith("<!doctype html><html lang=\"vi\"><head>"), served.body;
}

function HeadlessDocument(props: DocumentProps): NeonNode {
	const children = props.children;
	return <html><body>{children}</body></html>;
}

test "a document without a head is refused instead of dropping the page's head and styles" {
	let message = "";
	try {
		await serve({ routes: routes, notFound: <Text>app not found</Text>, client: "", document: HeadlessDocument }, "/");
	} catch (e) {
		message = (e as Error).message;
	}
	assert message.indexOf("wrote no <head>") >= 0, message;
}

test "a redirect route answers its status and location with no body" {
	const served = await serve(app, "/old");
	assert served.status === 307, served.status.toString();
	assert served.location === "/" && served.body === "", served.body;
}

test "a route that declares a status serves its page under that status" {
	const served = await serve(app, "/gone");
	assert served.status === 410 && served.location === null, served.status.toString();
	assert served.body.indexOf("this page is gone") > 0, served.body;
}

test "an address no route takes is a 404 through the app's not-found page" {
	const served = await serve(app, "/nowhere");
	assert served.status === 404 && served.location === null, served.status.toString();
	assert served.body.indexOf("app not found") > 0 && served.body.startsWith("<!doctype html>"), served.body;
}

test "two requests do not share a head or a response" {
	const first = await serve(app, "/");
	const second = await serve(app, "/gone");
	assert second.body.indexOf("Served home") < 0 && first.body.indexOf("this page is gone") < 0, second.body;
}

test "a route reads its request's url and headers, a header by any case of its name" {
	const phone = await serve(app, "/width", agent("Mozilla/5.0 (iPhone) Mobile Safari"));
	const desk = await serve(app, "/width?from=desk", agent("Mozilla/5.0 (Macintosh)"));
	assert phone.body.indexOf("width 390 for /width<") > 0, phone.body;
	assert desk.body.indexOf("width 1440 for /width?from=desk<") > 0, desk.body;
}

test "header names that differ only in case are one header, their values joined as Fetch joins them" {
	const headers = new Map<string, string>();
	headers.set("X-Tag", "a");
	headers.set("x-tag", "b");
	const served = await serve(app, "/tag", headers);
	assert served.body.indexOf("tag a, b<") > 0, served.body;
}

test "two requests in flight at once each render with their own request" {
	laterGate = new Gate();
	laterStarted = 0;
	const phone = serve(app, "/later", agent("Mobile"));
	const desk = serve(app, "/later", agent("Desktop"));
	assert laterStarted === 2, laterStarted.toString();
	await release(laterGate);
	const phoneBody = (await phone).body;
	const deskBody = (await desk).body;
	assert phoneBody.indexOf("ready width 390 for /later<") > 0, phoneBody;
	assert deskBody.indexOf("ready width 1440 for /later<") > 0, deskBody;
}

test "two requests in flight at once each render with the window size their own render published" {
	sizedGate = new Gate();
	const phone = serve(app, "/sized", agent("Mobile"));
	const desk = serve(app, "/sized", agent("Desktop"));
	await release(sizedGate);
	const phoneBody = (await phone).body;
	const deskBody = (await desk).body;
	assert phoneBody.indexOf("sized 390x800<") > 0, phoneBody;
	assert deskBody.indexOf("sized 1440x800<") > 0, deskBody;
}

test "a window read taken at module level is refused once the render published its own window" {
	let message = "";
	try {
		await serve(app, "/sizedAtModule", agent("Mobile"));
	} catch (e) {
		message = (e as Error).message;
	}
	assert message.indexOf("call it inside the component") >= 0, message;
}

test "outside a request there is no request event" {
	assert getRequestEvent() === null;
	let rooted: RequestEvent | null = null;
	let read = false;
	createRoot((dispose: Dispose): number => {
		rooted = getRequestEvent();
		read = true;
		return 0;
	});
	assert read && rooted === null;
	const bare = await serve(app, "/width");
	assert bare.body.indexOf("width 1440 for /width<") > 0, bare.body;
}

when (js) {
	import { Request, Response, fetchPage } from "../../src/render/serve";

	extern function fetchRequest(url: string, agent: string): Request from
		"new Request(#, { headers: [['User-Agent', #], ['X-Tag', 'a'], ['x-tag', 'b']] })";
	extern function bodyText(response: Response): Promise<string> from "#.text()";

	test "fetchPage hands the Fetch request's headers to the route" {
		const width = await bodyText(await fetchPage(app, fetchRequest("http://edge.test/width", "Mobile")));
		const tag = await bodyText(await fetchPage(app, fetchRequest("http://edge.test/tag", "Mobile")));
		assert width.indexOf("width 390 for /width<") > 0, width;
		assert tag.indexOf("tag a, b<") > 0, tag;
	}
}

test "a page served after a loose renderToString carries each base rule once" {
	const rulesIn = (body: string): number => body.split(":where(.neon-view)").length - 1;
	assert rulesIn((await serve(app, "/")).body) === 1, "before";
	renderToString(<View><Text>loose</Text></View>);
	const after = (await serve(app, "/")).body;
	assert rulesIn(after) === 1, after;
}
