import { createSignal } from "../../../src/core/signal";
import { NeonNode } from "../../../src/render/node";
import { View, Text } from "../../../src/components/primitives";
import { runApp } from "../../../src/platform/native/host";
import { connect } from "std/core/websocket";

export const IO_WAKE_PORT = 47913;

async function receive(report: (line: string) => void): Promise<void> {
	const opened = await connect(`ws://127.0.0.1:${IO_WAKE_PORT}/`);
	if (!opened.ok) {
		report(`NEON_IO_WAKE connect failed: ${opened.error.message}`);
		return;
	}
	const message = await opened.value.recv();
	if (!message.ok) {
		report(`NEON_IO_WAKE recv failed: ${message.error.message}`);
		return;
	}
	report(`NEON_IO_WAKE received ${message.value.data.length}`);
}

function IoWakeApp(): NeonNode {
	const [status, setStatus] = createSignal("waiting");
	receive((line: string): void => {
		console.log(line);
		setStatus(line);
	});
	return <View>
		<Text>{status()}</Text>
	</View>;
}

runApp(IoWakeApp);
