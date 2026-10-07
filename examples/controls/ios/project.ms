import { Project, Target } from "../../../../ion/tooling/generator/description";
import { bundlePrefix } from "../../../../ion/tooling/generator/plugins";

export const project: Project = {
	name: "NeonControls",
	targets: [Target.iosApp("NeonControls", "app.ms")],
	plugins: [bundlePrefix("dev.neon")],
};
