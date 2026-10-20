import { render, hydrate } from "../../src/render/host";
import { HostNode, NeonNode } from "../../src/render/hostTypes";
import { Head } from "../../src/render/head";
import { View } from "../../src/components/primitives";
import { createSignal, Accessor } from "../../src/core/signal";
import { flush } from "../../src/core/runtime";

when (js) {
	import { domHost } from "../../src/platform/browser/dom";
	import { HeadPage, servedPart } from "./servedApps";

	extern class Mount {
		extern remove(): void;
	}
	extern function servedPage(head: cstring, body: cstring): Mount from
		"((h, b) => { document.head.insertAdjacentHTML('afterbegin', h); const r=document.createElement('div');r.innerHTML=b;document.body.appendChild(r);return r; })(#, #)";
	extern function pageTitle(unused: int32): string from "(#, document.title)";
	extern function headCount(selector: cstring): number from "document.head.querySelectorAll(#).length";
	extern function headComments(unused: int32): number from "(#, Array.from(document.head.childNodes).filter(n => n.nodeType === 8).length)";
	extern function description(unused: int32): string from "(#, document.head.querySelector('meta[name=description]')?.content ?? '')";

	test "hydrate replaces the served head tags with the tree's own, and the title follows its signal" {
		const shellTitles = headCount("title");
		const mount = servedPage(servedPart("headPage", "head"), servedPart("headPage", "html"));
		assert pageTitle(0) === "Docs" && headCount("[data-neon-head]") === 2, pageTitle(0);

		const [title, setTitle] = createSignal("Docs");
		const dispose = hydrate(<HeadPage title={title} />, domHost(), mount as unknown as HostNode);
		try {
			assert headCount("[data-neon-head]") === 0, "served head tags are still there";
			assert headCount("title") === shellTitles + 1, "one title from the tree";
			assert pageTitle(0) === "Docs" && description(0) === "about this page", pageTitle(0);
			setTitle("Accounts");
			flush();
			assert pageTitle(0) === "Accounts", pageTitle(0);
		} finally { dispose(); mount.remove(); }
		assert description(0) === "", "the Head's tags stayed after dispose";
	}

	function Nested(props: { inner: Accessor<boolean> }): NeonNode {
		return <View>
			<Head>
				<title>Site</title>
				<meta name="description" content="the site" />
			</Head>
			<Show when={props.inner()}>
				<Head>
					<title>Page</title>
					<meta name="description" content="the page" />
					<meta name="robots" content="index" />
				</Head>
			</Show>
			<Head><meta name="robots" content="index" /></Head>
		</View>;
	}

	test "a browser reads the Head mounted last, and the one before it again once that leaves" {
		const mount = servedPage("", "");
		const [inner, setInner] = createSignal(true);
		const dispose = render(<Nested inner={inner} />, domHost(), mount as unknown as HostNode);
		try {
			assert pageTitle(0) === "Page" && description(0) === "the page", pageTitle(0) + " / " + description(0);
			setInner(false);
			flush();
			assert pageTitle(0) === "Site" && description(0) === "the site", pageTitle(0) + " / " + description(0);
			setInner(true);
			flush();
			assert pageTitle(0) === "Page" && description(0) === "the page", pageTitle(0) + " / " + description(0);
		} finally { dispose(); mount.remove(); }
	}

	test "the document holds one title and one meta of a key, whichever Head is mounted" {
		const shellTitles = headCount("title");
		const shellComments = headComments(0);
		const mount = servedPage("", "");
		const [inner, setInner] = createSignal(true);
		const dispose = render(<Nested inner={inner} />, domHost(), mount as unknown as HostNode);
		try {
			assert headCount("title") === shellTitles + 1, "titles with both mounted: " + headCount("title").toString();
			assert headCount("meta[name=robots]") === 1, "robots with both mounted: " + headCount("meta[name=robots]").toString();
			assert headCount("meta[name=description]") === 2, "descriptions that differ in content: " + headCount("meta[name=description]").toString();
			setInner(false);
			flush();
			assert headCount("title") === shellTitles + 1 && pageTitle(0) === "Site", "after the inner left: " + pageTitle(0);
			assert headCount("meta[name=robots]") === 1, "robots after the inner left: " + headCount("meta[name=robots]").toString();
			setInner(true);
			flush();
			assert headCount("title") === shellTitles + 1 && pageTitle(0) === "Page", "after the inner returned: " + pageTitle(0);
			assert headCount("meta[name=robots]") === 1, "robots after the inner returned: " + headCount("meta[name=robots]").toString();
		} finally { dispose(); mount.remove(); }
		assert headCount("title") === shellTitles && headCount("meta[name=robots]") === 0 && headComments(0) === shellComments,
			"left behind: " + headCount("title").toString() + " titles, " + headCount("meta[name=robots]").toString() + " robots, " + headComments(0).toString() + " comments";
	}
}
