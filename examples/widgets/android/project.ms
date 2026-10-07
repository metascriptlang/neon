import { Project, Target } from "../../../../ion/tooling/generator/description";
import { bundlePrefix } from "../../../../ion/tooling/generator/plugins";

export const project: Project = {
	name: "NeonWidgets",
	targets: [Target.androidApp("NeonWidgets", "app.ms")],
	plugins: [bundlePrefix("dev.neon")],
};
