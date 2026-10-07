import { Project, Target } from "../../../../ion/tooling/generator/description";
import { bundlePrefix } from "../../../../ion/tooling/generator/plugins";

export const project: Project = {
	name: "NeonCatalog",
	targets: [Target.iosApp("NeonCatalog", "app.ms")],
	plugins: [bundlePrefix("dev.neon")],
};
