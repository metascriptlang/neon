import { Accessor, Signal, accessor } from "../../src/core/signal";
import { Dispose } from "../../src/core/types";
import { NeonNode } from "../../src/render/hostTypes";
import { NeonEvent } from "../../src/render/event";
import { Head } from "../../src/render/head";
import { View, Text, Pressable } from "../../src/components/primitives";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import {
	RouteCodec,
	RoutePlan,
	RoutingError,
	RoutingRegistry,
	bindRoute,
	createRouteParticipant,
} from "../../src/navigation/routing";
import { RoutingHistory, createRoutingSession } from "../../src/navigation/routingHistory";

const HOME = "home";
const DOCS: string[] = ["start", "routing"];
const DOC_PREFIX = "/docs/";

const styles = createStyles({
	home: { padding: 24 },
	doc: { margin: 12 },
	tall: { height: 3000 },
});

export interface SiteModel {
	page: Accessor<string>;
	open: (url: string) => boolean;
	dispose: Dispose;
}

function pathOf(address: string): string {
	let end = address.length;
	const query = address.indexOf("?");
	const hash = address.indexOf("#");
	if (query >= 0) { end = query; }
	if (hash >= 0 && hash < end) { end = hash; }
	return address.substring(0, end);
}

function pageOf(address: string): string {
	const path = pathOf(address);
	if (path === "/") { return HOME; }
	if (!path.startsWith(DOC_PREFIX)) { return ""; }
	const slug = path.substring(DOC_PREFIX.length, path.length);
	return DOCS.indexOf(slug) >= 0 ? slug : "";
}

export function staticPaths(): string[] {
	const paths = ["/"];
	for (const slug of DOCS) { paths.push(DOC_PREFIX + slug); }
	return paths;
}

export function createSite(history: RoutingHistory): Result<SiteModel, RoutingError> {
	const address = new Signal<string>("/");
	const pageCodec: RouteCodec<string> = {
		id: "page",
		decode: (requested: string): Result<string, RoutingError> =>
			pageOf(requested) === "" ? Result.err(RoutingError.NoMatch) : Result.ok(requested),
		encode: (held: string): Result<string, RoutingError> => Result.ok(held),
	};
	const registry = new RoutingRegistry("main");
	registry.register(createRouteParticipant(
		"main",
		[
			bindRoute<string>(pageCodec,
				(): string | null => address.get(),
				(requested: string): void => address.set(requested)),
		],
		(): void => address.set("/"),
		(): string => address.get(),
		(state: string): Result<RoutePlan, RoutingError> => {
			if (pageOf(state) === "") { return Result.err(RoutingError.IncompleteSnapshot); }
			return Result.ok({ commit: (): void => address.set(state) });
		},
	));
	const session = try createRoutingSession(registry, history, (failure: RoutingError): void => {});
	return Result.ok({
		page: accessor((): string => pageOf(address.get())),
		open: (url: string): boolean => session.navigate(url, false).ok,
		dispose: (): void => session.dispose(),
	});
}

function Home(): NeonNode {
	return <View style={styles.home}>
		<Head><meta name="description" content="A Neon site served from the edge" /></Head>
		<h1>Neon site</h1>
	</View>;
}

function Doc(props: { slug: Accessor<string> }): NeonNode {
	const slug = props.slug;
	const reads = new Signal<int32>(0);
	return <View style={styles.doc}>
		<Head><meta name="description" content={"Docs: " + slug()} /></Head>
		<h1>{"Docs: " + slug()}</h1>
		<Pressable accessibilityLabel="Mark read" onPress={(e: NeonEvent): void => reads.set(reads.get() + 1)}>
			<Text>{"Read " + reads.get().toString()}</Text>
		</Pressable>
		<View style={styles.tall}></View>
		<h2 id="notes">Notes</h2>
	</View>;
}

export function Site(props: { model: SiteModel }): NeonNode {
	const page = props.model.page;
	return <View>
		<Head><title>{page() === HOME ? "Neon site" : page() + " · Neon site"}</title></Head>
		<nav>
			<a href="/">Home</a>
			<a href="/docs/start">Start</a>
			<a href="/docs/routing">Routing</a>
			<a href="/docs/routing#notes">Notes</a>
			<a href="/docs/missing">Missing</a>
			<a href="https://example.com/docs/start">Elsewhere</a>
		</nav>
		<Show when={page() === HOME}><Home /></Show>
		<Show when={page() !== HOME}><Doc slug={page} /></Show>
	</View>;
}

export function NotFound(): NeonNode {
	return <View>
		<Head>
			<title>Not found · Neon site</title>
			<meta name="robots" content="noindex" />
		</Head>
		<h1>Not found</h1>
		<a href="/">Home</a>
	</View>;
}
