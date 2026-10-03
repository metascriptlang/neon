import { Project, Target } from "../../../../ion/tooling/generator/description";
import { bundlePrefix } from "../../../../ion/tooling/generator/plugins";

export const project: Project = {
	name: "NeonList",
	targets: [Target.androidApp("NeonList", "app.ms")],
	plugins: [bundlePrefix("dev.neon")],
};
