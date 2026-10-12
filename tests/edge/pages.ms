import { createStyles, styleOf } from "../../src/macros/ui/style";
import { View, Text } from "../../src/components/primitives";
import { Host, HostNode, NeonNode } from "../../src/render/hostTypes";
import { renderToMarkup } from "../../src/render/ssr";

const styles = createStyles({
	home: { padding: 24 },
	guide: { margin: 12 },
});

function Home(): NeonNode {
	return <View style={styles.home}><Text>home page</Text></View>;
}

function Guide(): NeonNode {
	return <View style={styles.guide}><Text>guide page</Text></View>;
}

function Broken(): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		throw new Error("broken page");
	};
}

function page(path: string): string {
	let node: NeonNode = <Home />;
	if (path === "/guide") { node = <Guide />; }
	if (path === "/broken") { node = <Broken />; }
	const markup = renderToMarkup(node);
	return "<style>" + markup.css + "</style>" + markup.html;
}

extern function serve(render: (path: string) => string): void from "(globalThis.neonEdgePage = #)";

serve(page);
