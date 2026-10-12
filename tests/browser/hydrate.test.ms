import { renderToMarkup } from "../../src/render/ssr";
import { render, hydrate } from "../../src/render/host";
import { Host, HostNode, NeonNode } from "../../src/render/hostTypes";
import { NeonEvent } from "../../src/render/event";
import { View, Text, Pressable, ScrollView } from "../../src/components/primitives";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { createSignal, Accessor } from "../../src/core/signal";

when (js) {
	import { domHost } from "../../src/platform/browser/dom";
	const styles = createStyles({ box: { padding: 8 }, label: { color: "#334" } });

	extern class Page {
		textContent: string;
		extern remove(): void;
		extern click(): void;
	}
	extern function parsedPage(html: cstring): Page from
		"(s => { const r=document.createElement('div');r.innerHTML=s;document.body.appendChild(r);r.querySelectorAll('*').forEach(n=>{n.neonServed=true;});return r; })(#)";
	extern function emptyPage(tag: cstring): Page from "(t => { const r=document.createElement(t);document.body.appendChild(r);return r; })(#)";
	extern function pageNode(root: Page, selector: cstring): Page from "(#).querySelector(#)";
	extern function addForeignChild(node: Page): void from "(n => { const f=document.createElement('i');f.id='foreign';n.appendChild(f); })(#)";
	extern function notServed(root: Page): number from
		"(r => Array.from(r.querySelectorAll('*')).filter(n=>n.neonServed!==true&&n.id!=='foreign').length)(#)";
	extern function fireScroll(node: Page): void from "(n => n.dispatchEvent(new Event('scroll')))(#)";
	extern function shape(root: Page): string from
		"(r => { const f=n=>n.nodeType===1?[n.localName,Array.from(n.attributes,a=>[a.name,a.name==='class'?a.value.split(/\\s+/).sort().join(' '):a.value]).sort((a,b)=>a[0].localeCompare(b[0])),n.id==='mech'?[]:Array.from(n.childNodes,f)]:n.nodeType===3?n.data:'comment '+n.data;return JSON.stringify(Array.from(r.childNodes,f)); })(#)";

	function docs(
		name: Accessor<string>,
		blank: Accessor<string>,
		open: Accessor<boolean>,
		rows: Accessor<string[]>,
		press: (e: NeonEvent) => void,
		mech: (n: HostNode) => void,
	): NeonNode {
		return <View accessibilityLabel="Docs" style={styles.box}>
			<Text style={styles.label}>Hi {name()}</Text>
			<Text>{blank()}</Text>
			<Pressable accessibilityLabel="Copy" onPress={press}><Text>copy</Text></Pressable>
			<Show when={open()}><p id="shown">shown</p></Show>
			<For each={rows()}>{(row: string, i: Accessor<number>): NeonNode => <span class="row">{row}</span>}</For>
			<canvas id="mech" ref={mech}></canvas>
			<a href="/docs" title={name()}>docs &amp; more</a>
		</View>;
	}

	function freshShape(name: string, open: boolean, rows: string[]): string {
		const [n, _n] = createSignal(name);
		const [b, _b] = createSignal("");
		const [o, _o] = createSignal(open);
		const [r, _r] = createSignal<string[]>(rows);
		const mount = emptyPage("div");
		const dispose = render(docs(n, b, o, r, (e: NeonEvent): void => {}, (node: HostNode): void => {}), domHost(), mount as unknown as HostNode);
		const s = shape(mount);
		dispose();
		mount.remove();
		return s;
	}

	test "hydrate attaches a tree to a parsed page without creating an element" {
		const [n, _n] = createSignal("Ann");
		const [b, _b] = createSignal("");
		const [o, _o] = createSignal(true);
		const [r, _r] = createSignal<string[]>(["a", "b", "c"]);
		const sent = renderToMarkup(docs(n, b, o, r, (e: NeonEvent): void => {}, (node: HostNode): void => {})).html;
		assert sent.indexOf("<!---->") >= 0 && sent.indexOf("<!--!-->") >= 0, sent;

		const mount = parsedPage(sent);
		addForeignChild(pageNode(mount, "#mech"));
		const [name, setName] = createSignal("Ann");
		const [blank, setBlank] = createSignal("");
		const [open, setOpen] = createSignal(true);
		const [rows, setRows] = createSignal<string[]>(["a", "b", "c"]);
		let pressed = 0;
		let mech: HostNode | null = null;
		let made = 0;
		const host: Host = domHost();
		const create = host.createElement;
		host.createElement = (tag: string): HostNode => { made += 1; return create(tag); };

		const dispose = hydrate(
			docs(name, blank, open, rows, (e: NeonEvent): void => { pressed += 1; }, (node: HostNode): void => { mech = node; }),
			host, mount as unknown as HostNode);
		try {
			assert made === 0, "the host created " + made.toString() + " elements";
			assert notServed(mount) === 0, notServed(mount).toString() + " elements are not the page's own";
			assert shape(mount) === freshShape("Ann", true, ["a", "b", "c"]), shape(mount);
			assert mech === (pageNode(mount, "#mech") as unknown as HostNode), "the ref received the page's canvas";
			assert pageNode(mount, "#mech #foreign") !== null, "the canvas lost the child it was given";

			pageNode(mount, "[aria-label=Copy]").click();
			assert pressed === 1, "pressed " + pressed.toString();

			setName("Bob");
			setBlank("now");
			setOpen(false);
			setRows(["c", "a"]);
			assert notServed(mount) === 0, "an update replaced a served element";
			const [n2, _n2] = createSignal("Bob");
			assert pageNode(mount, "span").textContent === "Hi Bob", pageNode(mount, "span").textContent;
			setBlank("");
			assert shape(mount) === freshShape("Bob", false, ["c", "a"]), shape(mount);

			setOpen(true);
			setRows(["a", "d", "c"]);
			assert shape(mount) === freshShape("Bob", true, ["a", "d", "c"]), shape(mount);
			assert made === 2, "one new row and the reopened branch are the only elements created: " + made.toString();
		} finally { dispose(); mount.remove(); }
	}

	test "hydrate on a page from another tree fails before the page is shown wrong" {
		const mount = parsedPage("<div class=\"neon-view\"><p>b</p></div>");
		let said = "";
		try {
			hydrate(<View><h1>b</h1></View>, domHost(), mount as unknown as HostNode);
		} catch (e) { said = e.toString(); }
		mount.remove();
		assert said.indexOf("<h1>") >= 0 && said.indexOf("child 1 of view") >= 0, said;
	}

	function rendered(app: NeonNode): string {
		const mount = emptyPage("div");
		const dispose = render(app, domHost(), mount as unknown as HostNode);
		const result = shape(mount);
		dispose();
		mount.remove();
		return result;
	}

	test "hydrate takes over a served ScrollView and leaves it scrollable" {
		let scrolls = 0;
		const app: NeonNode = <View>
			<ScrollView horizontal={true} showsHorizontalScrollIndicator={false}
				onScroll={(e: NeonEvent): void => { scrolls += 1; }}>
				<Text>row</Text>
			</ScrollView>
		</View>;
		const mount = parsedPage(renderToMarkup(app).html);
		let made = 0;
		const host: Host = domHost();
		const create = host.createElement;
		host.createElement = (tag: string): HostNode => { made += 1; return create(tag); };
		const dispose = hydrate(app, host, mount as unknown as HostNode);
		try {
			assert made === 0, "the host created " + made.toString() + " elements";
			assert notServed(mount) === 0, notServed(mount).toString() + " elements are not the page's own";
			fireScroll(pageNode(mount, ".neon-scrollview"));
			assert scrolls === 1, "onScroll ran " + scrolls.toString() + " times";
			assert shape(mount) === rendered(app), shape(mount);
		} finally { dispose(); mount.remove(); }
	}
}
