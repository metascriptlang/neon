import { Counter } from "./counter";
import { Void } from "../../src/components/primitives";
import { runWindow, DesktopOptions, desktopOptions } from "../../src/platform/ion/window";
import { exit } from "std/process";

function App(): NeonNode {
	return <Void style={{ backgroundColor: "#1e1e2e" }}>
		<Counter />
	</Void>;
}

const opts: DesktopOptions = { ...desktopOptions("Neon refresh window", 480, 320), font: "../../../void/assets/font.ttf" };
exit(runWindow(opts, App));
