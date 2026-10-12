import { renderToString } from "../../src/render/ssr";
import { render } from "../../src/render/host";
import { HostNode, NeonNode } from "../../src/render/hostTypes";
import { View, Text, Pressable, TextInput } from "../../src/components/primitives";
import { collectCss, resetCss } from "../../src/render/sheet";
import { createStyles, styleOf } from "../../src/macros/ui/style";

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
		"(s => { const r=document.createElement('div');r.innerHTML=s;const f=n=>n.nodeType===1?[n.localName,Array.from(n.attributes,a=>[a.name,a.name==='class'?a.value.split(/\\s+/).sort().join(' '):a.name==='style'?n.style.cssText:a.value]).sort((a,b)=>a[0].localeCompare(b[0])),Array.from(n.childNodes,f)]:n.nodeType===3?n.data:null;return JSON.stringify(Array.from(r.childNodes,f));})(#)";

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
}
