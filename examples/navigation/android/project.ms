import { Project, Target } from "../../../../ion/tooling/generator/description";
import { bundlePrefix } from "../../../../ion/tooling/generator/plugins";

export const project: Project = {
	name: "NeonNavigation",
	targets: [Target.androidApp("NeonNavigation", "app.ms")],
	plugins: [bundlePrefix("dev.neon")],
};
