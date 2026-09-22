import { Project, Target } from "../../../ion/tooling/generator/description";
import { bundlePrefix } from "../../../ion/tooling/generator/plugins";

export const project: Project = {
	name: "NeonCounter",
	targets: [Target.iosApp("NeonCounter", "app.ms")],
	plugins: [bundlePrefix("dev.neon")],
};
