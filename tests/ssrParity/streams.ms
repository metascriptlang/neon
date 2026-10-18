import { sleepAsync } from "std/core/promise";
import { NeonNode, el, text, dynText } from "../../src/render/node";
import { Host, HostNode } from "../../src/render/hostTypes";
import { renderToStream } from "../../src/render/ssr";
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

class Flag {
	up: boolean = false;
}

// The outer boundary settles only after the quick sibling's fragment was written, so the chunk order holds under any load.
async function afterFlag(flag: Flag, value: int32): Promise<int32> {
	while (!flag.up) { await sleepAsync(1); }
	return value;
}

function readingAfter(name: string, flag: Flag, value: int32): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const data = createAsyncMemo((p: int32 | null): Promise<int32> => afterFlag(flag, value));
		el("p", [], [], dynText((): string => name + "=" + data().toString()))(host, parent, before);
	};
}

function page(quickWritten: Flag): NeonNode {
	return <View style={looks.shell}>
		<Text>top</Text>
		<Loading fallback={<Text>wait outer</Text>}>
			{readingAfter("outer", quickWritten, 1)}
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
	const quickWritten = new Flag();
	const r = renderToStream(page(quickWritten));
	r.pipe({ write: (chunk: string): void => { chunks.push(chunk); if (chunks.length >= 2) { quickWritten.up = true; } }, end: (): void => { ended += 1; } });
	await r;
	for (let i = 0; i < chunks.length; i += 1) { console.log("chunk " + i.toString() + ": " + chunks[i]); }
	console.log("ended " + ended.toString());
}
main();
