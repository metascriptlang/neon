import { Project, Target } from "../../../../ion/tooling/generator/description";
import { bundlePrefix } from "../../../../ion/tooling/generator/plugins";

export const project: Project = {
	name: "NeonFlatList",
	targets: [Target.androidApp("NeonFlatList", "app.ms")],
	plugins: [bundlePrefix("dev.neon")],
};
