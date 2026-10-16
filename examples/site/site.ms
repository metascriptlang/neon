import { Signal } from "../../src/core/signal";
import { NeonNode } from "../../src/render/hostTypes";
import { NeonEvent } from "../../src/render/event";
import { Head } from "../../src/render/head";
import { createAsyncMemo } from "../../src/render/hydrateMemo";
import { Loading } from "../../src/macros/ui/flow";
import { View, Text, Pressable } from "../../src/components/primitives";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { GuardDecision, RouteMatch, notFound, proceed } from "../../src/navigation/route";
import { A, LayoutProps, Routes, createRoutes, useParams } from "../../src/navigation/router";

const DOCS: string[] = ["start", "routing"];
const NOTES: string[] = ["alpha", "beta"];

export struct Note {
	slug: string;
	text: string;
}

export function noteOf(slug: string, via: string): Note {
	return { slug: slug, text: "Note " + slug + " read " + via };
}

when (server) {
	import { sleepAsync } from "std/core/promise";

	async function loadNote(slug: string): Promise<Note> {
		await sleepAsync(5);
		return noteOf(slug, "at render");
	}
} else {
	extern function fetchNote(url: cstring): Promise<Note> from "fetch(#).then((answer) => answer.json())";

	function loadNote(slug: string): Promise<Note> {
		return fetchNote("/api/note/" + slug);
	}
}

const styles = createStyles({
	home: { padding: 24 },
	doc: { margin: 12 },
	tall: { height: 3000 },
});

function Layout(props: LayoutProps): NeonNode {
	return <View>
		<nav>
			<A href="/">Home</A>
			<A href="/docs/start">Start</A>
			<A href="/docs/routing">Routing</A>
			<A href="/docs/routing#notes">Notes</A>
			<A href="/docs/missing">Missing</A>
			<a href="https://example.com/docs/start">Elsewhere</a>
		</nav>
		{props.children}
	</View>;
}

function Home(): NeonNode {
	return <View style={styles.home}>
		<Head>
			<title>Neon site</title>
			<meta name="description" content="A Neon site served from the edge" />
		</Head>
		<h1>Neon site</h1>
	</View>;
}

function Doc(): NeonNode {
	const slug = useParams().get("slug") ?? "";
	const reads = new Signal<int32>(0);
	return <View style={styles.doc}>
		<Head>
			<title>{slug + " · Neon site"}</title>
			<meta name="description" content={"Docs: " + slug} />
		</Head>
		<h1>{"Docs: " + slug}</h1>
		<Pressable accessibilityLabel="Mark read" onPress={(e: NeonEvent): void => reads.set(reads.get() + 1)}>
			<Text>{"Read " + reads.get().toString()}</Text>
		</Pressable>
		<View style={styles.tall}></View>
		<h2 id="notes">Notes</h2>
	</View>;
}

function NoteBody(props: { slug: string }): NeonNode {
	const note = createAsyncMemo((previous: Note | null): Promise<Note> => loadNote(props.slug));
	return <p id="note">{note().text}</p>;
}

function Notes(): NeonNode {
	const slug = useParams().get("slug") ?? "";
	return <View style={styles.doc}>
		<Head>
			<title>{slug + " · Neon notes"}</title>
		</Head>
		<h1>{"Note: " + slug}</h1>
		<Loading fallback={<p>Loading note</p>}>
			<NoteBody slug={slug} />
		</Loading>
	</View>;
}

export function NotFound(): NeonNode {
	return <View>
		<Head>
			<title>Not found · Neon site</title>
			<meta name="robots" content="noindex" />
		</Head>
		<h1>Not found</h1>
	</View>;
}

function knownDoc(params: Map<string, string>, found: RouteMatch): GuardDecision {
	return DOCS.indexOf(params.get("slug") ?? "") >= 0 ? proceed() : notFound();
}

function knownNote(params: Map<string, string>, found: RouteMatch): GuardDecision {
	return NOTES.indexOf(params.get("slug") ?? "") >= 0 ? proceed() : notFound();
}

function docPaths(): Map<string, string>[] {
	const all: Map<string, string>[] = [];
	for (const slug of DOCS) {
		const values = new Map<string, string>();
		values.set("slug", slug);
		all.push(values);
	}
	return all;
}

export const routes: Routes = createRoutes([
	{ layout: Layout, children: [
		{ path: "/", component: Home },
		{ path: "/docs/:slug", component: Doc, guard: knownDoc, paths: docPaths },
		{ path: "/notes/:slug", component: Notes, guard: knownNote },
		{ path: "*", status: 404, component: NotFound },
	] },
]);

export function staticPaths(): string[] {
	const paths = routes.tree.staticPaths();
	if (!paths.ok) { throw new Error("site: static paths: " + paths.error.toString()); }
	return paths.value;
}
