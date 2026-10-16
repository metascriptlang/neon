import { createSignal } from "../../src/core/signal";
import { renderToMarkup } from "../../src/render/ssr";
import { Head } from "../../src/render/head";
import { View, Text } from "../../src/components/primitives";
import { Layout, Page } from "./headPages";

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
