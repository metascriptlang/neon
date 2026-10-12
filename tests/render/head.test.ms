import { NeonNode } from "../../src/render/node";
import { createSignal, Accessor } from "../../src/core/signal";
import { render, hydrate, mockHost, mockNode, mockToString, MockNode, HostNode } from "../../src/render/host";
import { renderToMarkup } from "../../src/render/ssr";
import { Head } from "../../src/render/head";
import { View, Text } from "../../src/components/primitives";

function Page(props: { title: Accessor<string> }): NeonNode {
	return <View>
		<Head>
			<title>{props.title()}</title>
			<meta name="description" content="the page's own" />
			<meta name="robots" content="index" />
		</Head>
		<Text>body</Text>
	</View>;
}

function Layout(props: { children: NeonNode }): NeonNode {
	return <View>
		<Head>
			<title>Site</title>
			<meta name="description" content="the layout's" />
			<meta name="theme-color" content="#101418" />
			<meta name="robots" content="index" />
			<link rel="canonical" href="/docs?a=1&b=2" />
		</Head>
		{props.children}
	</View>;
}

test "a server render returns what Head holds beside the body, not inside it" {
	const [title, _t] = createSignal("Docs & more");
	const page = renderToMarkup(<Page title={title} />);
	assert page.html.indexOf("<title") < 0 && page.html.indexOf("body") >= 0, page.html;
	assert page.head === "<title data-neon-head=\"\">Docs &amp; more</title>" +
		"<meta name=\"description\" content=\"the page&#39;s own\" data-neon-head=\"\">" +
		"<meta name=\"robots\" content=\"index\" data-neon-head=\"\">", page.head;
}

test "the innermost Head wins a title and a meta of one name and content, a meta that differs in content stays" {
	const [title, _t] = createSignal("Accounts");
	const page = renderToMarkup(<Layout><Page title={title} /></Layout>);
	assert page.head === "<title data-neon-head=\"\">Accounts</title>" +
		"<meta name=\"description\" content=\"the page&#39;s own\" data-neon-head=\"\">" +
		"<meta name=\"robots\" content=\"index\" data-neon-head=\"\">" +
		"<meta name=\"description\" content=\"the layout&#39;s\" data-neon-head=\"\">" +
		"<meta name=\"theme-color\" content=\"#101418\" data-neon-head=\"\">" +
		"<link rel=\"canonical\" href=\"/docs?a=1&amp;b=2\" data-neon-head=\"\">", page.head;
}

test "metas of one name that differ in media both stay" {
	const page = renderToMarkup(<View>
		<Head>
			<meta name="theme-color" media="(prefers-color-scheme: light)" content="#fff" />
			<meta name="theme-color" media="(prefers-color-scheme: dark)" content="#000" />
		</Head>
	</View>);
	assert page.head.indexOf("content=\"#fff\"") >= 0 && page.head.indexOf("content=\"#000\"") >= 0, page.head;
}

test "two requests do not share a head" {
	const [a, _a] = createSignal("A");
	const [b, _b] = createSignal("B");
	const first = renderToMarkup(<Page title={a} />).head;
	const second = renderToMarkup(<Page title={b} />).head;
	assert first.indexOf(">A<") >= 0 && second.indexOf(">B<") >= 0 && second.indexOf(">A<") < 0, first + " | " + second;
	assert renderToMarkup(<Text>no head</Text>).head === "", "a page without Head";
}

test "on a client the title follows its signal and leaves with its Head" {
	const [title, setTitle] = createSignal("One");
	const [shown, setShown] = createSignal(true);
	const host = mockHost();
	const root = mockNode("root");
	render(<View><Show when={shown()}><Page title={title} /></Show></View>, host, root as unknown as HostNode);
	const head = (host.headRoot as (n: HostNode) => HostNode)(root as unknown as HostNode) as unknown as MockNode;
	assert mockToString(head).indexOf("<title>One</title>") >= 0, mockToString(head);
	setTitle("Two");
	assert mockToString(head).indexOf("<title>Two</title>") >= 0, mockToString(head);
	setShown(false);
	assert mockToString(head) === "<head></head>", mockToString(head);
}

test "the Head mounted last comes first, where a browser reads the title" {
	const [title, _t] = createSignal("Page");
	const host = mockHost();
	const root = mockNode("root");
	render(<Layout><Page title={title} /></Layout>, host, root as unknown as HostNode);
	const head = (host.headRoot as (n: HostNode) => HostNode)(root as unknown as HostNode) as unknown as MockNode;
	assert mockToString(head).indexOf("<head><title>Page</title>") === 0, mockToString(head);
}

test "a host with no head renders the rest of the tree" {
	const [title, _t] = createSignal("Docs");
	const host = mockHost();
	host.headRoot = null;
	const root = mockNode("root");
	render(<Page title={title} />, host, root as unknown as HostNode);
	assert mockToString(root) === "<root><view><text>body</text></view></root>", mockToString(root);
}

test "hydrate reads the body from the page and mounts what Head holds fresh" {
	const [title, _t] = createSignal("Docs");
	const root = mockNode("root");
	render(<Page title={title} />, mockHost(), root as unknown as HostNode, "")();
	const before = mockToString(root);
	const host = mockHost();
	hydrate(<Page title={title} />, host, root as unknown as HostNode);
	assert mockToString(root) === before, mockToString(root);
	const head = (host.headRoot as (n: HostNode) => HostNode)(root as unknown as HostNode) as unknown as MockNode;
	assert mockToString(head).indexOf("<head><title>Docs</title>") === 0, mockToString(head);
}
