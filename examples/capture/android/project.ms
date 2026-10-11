import { Project, Target } from "../../../../ion/tooling/generator/description";
import { bundlePrefix } from "../../../../ion/tooling/generator/plugins";

export const project: Project = {
	name: "NeonCapture",
	targets: [Target.androidApp("NeonCapture", "app.ms")],
	plugins: [bundlePrefix("dev.neon")],
};
