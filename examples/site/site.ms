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

function knownPage(page: string): boolean {
	return page === HOME || DOCS.indexOf(page) >= 0;
}

export function createSite(history: RoutingHistory): Result<SiteModel, RoutingError> {
	const page = new Signal<string>(HOME);
	const homeCodec: RouteCodec<string> = {
		id: "home",
		decode: (address: string): Result<string, RoutingError> =>
			address === "/" ? Result.ok(HOME) : Result.err(RoutingError.NoMatch),
		encode: (name: string): Result<string, RoutingError> => Result.ok("/"),
	};
	const docCodec: RouteCodec<string> = {
		id: "doc",
		decode: (address: string): Result<string, RoutingError> => {
			if (!address.startsWith(DOC_PREFIX)) { return Result.err(RoutingError.NoMatch); }
			const slug = address.substring(DOC_PREFIX.length, address.length);
			return DOCS.indexOf(slug) >= 0 ? Result.ok(slug) : Result.err(RoutingError.NoMatch);
		},
		encode: (slug: string): Result<string, RoutingError> => Result.ok(DOC_PREFIX + slug),
	};
	const registry = new RoutingRegistry("main");
	registry.register(createRouteParticipant(
		"main",
		[
			bindRoute<string>(homeCodec,
				(): string | null => page.get() === HOME ? HOME : null,
				(name: string): void => page.set(HOME)),
			bindRoute<string>(docCodec,
				(): string | null => page.get() === HOME ? null : page.get(),
				(slug: string): void => page.set(slug)),
		],
		(): void => page.set(HOME),
		(): string => page.get(),
		(state: string): Result<RoutePlan, RoutingError> => {
			if (!knownPage(state)) { return Result.err(RoutingError.IncompleteSnapshot); }
			return Result.ok({ commit: (): void => page.set(state) });
		},
	));
	const session = try createRoutingSession(registry, history, (failure: RoutingError): void => {});
	return Result.ok({
		page: accessor((): string => page.get()),
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
