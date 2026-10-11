import { Project, Target } from "../../../../ion/tooling/generator/description";
import { bundlePrefix } from "../../../../ion/tooling/generator/plugins";

export const project: Project = {
	name: "NeonApis",
	targets: [Target.iosApp("NeonApis", "app.ms")],
	plugins: [bundlePrefix("dev.neon")],
};
