import { Project, Target } from "../../../../ion/tooling/generator/description";
import { bundlePrefix } from "../../../../ion/tooling/generator/plugins";

export const project: Project = {
	name: "NeonChurn",
	targets: [Target.androidApp("NeonChurn", "app.ms")],
	plugins: [bundlePrefix("dev.neon")],
};
