import { Project, Target } from "../../../../ion/tooling/generator/description";
import { bundlePrefix } from "../../../../ion/tooling/generator/plugins";

export const project: Project = {
	name: "NeonWidgets",
	targets: [Target.iosApp("NeonWidgets", "app.ms")],
	plugins: [bundlePrefix("dev.neon")],
};
