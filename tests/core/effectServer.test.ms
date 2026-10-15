import { onMount } from "../../src/core/effect";
import { HostNode } from "../../src/render/host";
import { renderToString } from "../../src/render/ssr";
import { NeonNode } from "../../src/render/node";
import { View, TextInput } from "../../src/components/primitives";

interface FocusProps { log: string[]; }

function Focus(props: FocusProps): NeonNode {
	const log = props.log;
	let input: HostNode | null = null;
	onMount(() => { log.push(input === null ? "null" : "node"); });
	return <View><TextInput ref={(n: HostNode): void => { input = n; }} /></View>;
}

test "effects and onMount do not run on the server" {
	const log: string[] = [];
	const html = renderToString(<Focus log={log} />);
	assert log.length === 0, "got " + log.join(",");
	assert html !== "", "the page still renders";
}
