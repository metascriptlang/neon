import { NeonNode } from "../../src/render/hostTypes";
import { createAsyncMemo } from "../../src/core/memo";
import { Loading } from "../../src/macros/ui/flow";
import { View, Text } from "../../src/components/primitives";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { dynText, el } from "../../src/render/node";
import { renderToStream, readable } from "../../src/render/ssr";

extern class ReadableStream {}

const looks = createStyles({ page: { padding: 6 }, late: { margin: 2 } });

async function held(gate: Promise<int32>): Promise<int32> {
	return await gate;
}

function slowText(gate: Promise<int32>): NeonNode {
	return (host, parent, before): void => {
		const data = createAsyncMemo((p: int32 | null): Promise<int32> => held(gate));
		el("p", [], [], dynText((): string => "slow=" + data().toString()))(host, parent, before);
	};
}

function slowPage(gate: Promise<int32>): NeonNode {
	return <View style={looks.page}>
		<Text>head</Text>
		<Loading fallback={<Text>waiting</Text>}>
			{slowText(gate)}
			<View style={looks.late}><Text>after the wait</Text></View>
		</Loading>
		<Text>tail</Text>
	</View>;
}

export function slowStream(gate: Promise<int32>): ReadableStream {
	return readable(renderToStream(slowPage(gate)));
}

export async function slowAwaited(gate: Promise<int32>): Promise<string> {
	const out = await renderToStream(slowPage(gate));
	return "<style>" + out.css + "</style>" + out.html;
}
