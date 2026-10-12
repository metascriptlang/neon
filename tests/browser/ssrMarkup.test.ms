import { renderToString } from "../../src/render/ssr";
import { render } from "../../src/render/host";
import { HostNode, NeonNode } from "../../src/render/hostTypes";
import { View, Text, Pressable, TextInput, ScrollView } from "../../src/components/primitives";
import { collectCss, resetCss } from "../../src/render/sheet";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { createSignal, Accessor } from "../../src/core/signal";

when (js) {
	import { domHost } from "../../src/platform/browser/dom";
	const styles = createStyles({ box: { padding: 8 }, label: { color: "#334" } });

	extern class MarkupElement {
		innerHTML: string;
		extern appendChild(node: MarkupElement): void;
		extern remove(): void;
	}
	extern class document {
		static body: MarkupElement;
		static extern createElement(tag: cstring): MarkupElement;
	}
	extern function normalizedHtml(html: cstring): string from
		"(s => { const r=document.createElement('div');r.innerHTML=s;const f=n=>n.nodeType===1?[n.localName,Array.from(n.attributes,a=>[a.name,a.name==='class'?a.value.split(/\\s+/).sort().join(' '):a.name==='style'?n.style.cssText:a.value]).filter(a=>a[0]!=='checked').concat(n.localName==='input'&&n.type==='checkbox'?[['checked property',String(n.checked)]]:[]).sort((a,b)=>a[0].localeCompare(b[0])),n.localName==='textarea'?[n.value]:Array.from(n.childNodes,f)]:n.nodeType===3?n.data:null;return JSON.stringify(Array.from(r.childNodes,f));})(#)";

	test "server primitive classes and attributes match actual DOM host" {
		assert styles.box.cssId !== null && styles.label.cssId !== null;
		const app: NeonNode = <View accessibilityLabel="Page" style={styles.box}>
			<Text style={styles.label}>café &amp; · …</Text>
			<Pressable accessibilityLabel="Open"><Text>go</Text></Pressable>
			<TextInput editable={false} secureTextEntry={true} keyboardType="number-pad" maxLength={4}
				autoCorrect={false} accessibilityRole="search" placeholder="PIN" />
			<TextInput editable={true} autoFocus={false} accessibilityLabel="Name" />
		</View>;
		resetCss();
		const server = renderToString(app);
		assert collectCss().indexOf("white-space:pre-wrap") >= 0;
		const mount = document.createElement("div");
		document.body.appendChild(mount);
		const dispose = render(app, domHost(), mount as unknown as HostNode);
		try {
			assert normalizedHtml(server) === normalizedHtml(mount.innerHTML),
				server + " vs " + mount.innerHTML;
		} finally { dispose(); mount.remove(); }
	}

	extern function parsedNodes(html: cstring): string from
		"(s => { const r=document.createElement('div');r.innerHTML=s;const f=n=>n.nodeType===1?[n.localName,Array.from(n.childNodes,f).filter(x=>x!==undefined)]:n.nodeType===3?n.data:n.data===''?'':n.data==='!'?undefined:'comment '+n.data;return JSON.stringify(Array.from(r.childNodes,f).filter(x=>x!==undefined));})(#)";
	extern function liveNodes(mount: MarkupElement): string from
		"(r => { const f=n=>n.nodeType===1?[n.localName,Array.from(n.childNodes,f)]:n.nodeType===3?n.data:'comment '+n.data;return JSON.stringify(Array.from(r.childNodes,f));})(#)";

	test "server text marks give a parsed page the node list the DOM host builds" {
		const [on, _on] = createSignal(false);
		const [open, _open] = createSignal(true);
		const [blank, _blank] = createSignal("");
		const [count, _count] = createSignal(3);
		const [rows, _rows] = createSignal<string[]>(["a", "b"]);
		const app: NeonNode = <View>
			<Text>count: {count().toString()} items</Text>
			<Text>{blank()}</Text>
			<Show when={on()}><Text>hidden</Text></Show>
			<Show when={open()}><Text>shown</Text></Show>
			<For each={rows()}>{(row: string, i: Accessor<number>): NeonNode => <Text>{row}</Text>}</For>
			<Text>tail</Text>
		</View>;
		const server = renderToString(app);
		assert server.indexOf("<!---->") >= 0 && server.indexOf("<!--!-->") >= 0, server;
		const mount = document.createElement("div");
		document.body.appendChild(mount);
		const dispose = render(app, domHost(), mount as unknown as HostNode);
		try {
			assert parsedNodes(server) === liveNodes(mount), parsedNodes(server) + " vs " + liveNodes(mount);
		} finally { dispose(); mount.remove(); }
	}

	function serverAndDom(app: NeonNode): string[] {
		resetCss();
		const server = renderToString(app);
		const mount = document.createElement("div");
		document.body.appendChild(mount);
		const dispose = render(app, domHost(), mount as unknown as HostNode);
		const dom = mount.innerHTML;
		dispose();
		mount.remove();
		return [server, dom];
	}

	test "server ScrollView is the element and classes the DOM host builds" {
		const app: NeonNode = <View>
			<ScrollView horizontal={false}><Text>row</Text></ScrollView>
		</View>;
		const [server, dom] = serverAndDom(app);
		assert normalizedHtml(server) === normalizedHtml(dom), server + " vs " + dom;
	}

	test "server Text numberOfLines is the classes the DOM host builds" {
		const app: NeonNode = <View>
			<Text numberOfLines={2}>long</Text>
			<Text numberOfLines={0}>free</Text>
		</View>;
		const [server, dom] = serverAndDom(app);
		assert normalizedHtml(server) === normalizedHtml(dom), server + " vs " + dom;
		assert server.indexOf("numberOfLines") < 0, server;
		const css = collectCss();
		assert css.indexOf(".neon-lines-2{-webkit-line-clamp:2}") >= 0 && css.indexOf(".neon-lines{") >= 0, css;
	}
}
