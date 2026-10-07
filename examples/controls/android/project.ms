import { Project, Target } from "../../../../ion/tooling/generator/description";
import { bundlePrefix } from "../../../../ion/tooling/generator/plugins";

export const project: Project = {
	name: "NeonControls",
	targets: [Target.androidApp("NeonControls", "app.ms")],
	plugins: [bundlePrefix("dev.neon")],
};
