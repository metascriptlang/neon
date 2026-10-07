import { Project, Target } from "../../../../ion/tooling/generator/description";
import { bundlePrefix } from "../../../../ion/tooling/generator/plugins";

export const project: Project = {
	name: "NeonScrollMatrix",
	targets: [Target.iosApp("NeonScrollMatrix", "app.ms")],
	plugins: [bundlePrefix("dev.neon")],
};
