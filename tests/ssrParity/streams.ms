import { sleepAsync } from "std/core/promise";
import { NeonNode, el, text, dynText } from "../../src/render/node";
import { Host, HostNode } from "../../src/render/hostTypes";
import { streamRender } from "../../src/render/ssr";
import { createAsyncMemo } from "../../src/core/memo";
import { Loading } from "../../src/macros/ui/flow";
import { View, Text } from "../../src/components/primitives";
import { createStyles, styleOf } from "../../src/macros/ui/style";

const looks = createStyles({ shell: { padding: 4 }, late: { padding: 11 } });

async function after(ms: int32, value: int32): Promise<int32> {
	await sleepAsync(ms);
	return value;
}

function reading(name: string, ms: int32, value: int32): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const data = createAsyncMemo((p: int32 | null): Promise<int32> => after(ms, value));
		el("p", [], [], dynText((): string => name + "=" + data().toString()))(host, parent, before);
	};
}

function page(): NeonNode {
	return <View style={looks.shell}>
		<Text>top</Text>
		<Loading fallback={<Text>wait outer</Text>}>
			{reading("outer", 40, 1)}
			<View style={looks.late}><Text>{"a < b & \"c\""}</Text></View>
			<Loading fallback={<Text>wait inner</Text>}>{reading("inner", 30, 2)}</Loading>
		</Loading>
		<Loading fallback={<Text>wait quick</Text>}>{reading("quick", 5, 3)}</Loading>
		<Text>bottom</Text>
	</View>;
}

async function main(): Promise<void> {
	const chunks: string[] = [];
	let ended = 0;
	const r = streamRender(page());
	r.pipe({ write: (chunk: string): void => { chunks.push(chunk); }, end: (): void => { ended += 1; } });
	await r.markup();
	for (let i = 0; i < chunks.length; i += 1) { console.log("chunk " + i.toString() + ": " + chunks[i]); }
	console.log("ended " + ended.toString());
}
main();
