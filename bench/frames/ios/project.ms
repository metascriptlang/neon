import { Project, Target, plistBoolean } from "../../../../ion/tooling/generator/description";
import { bundlePrefix } from "../../../../ion/tooling/generator/plugins";

export const project: Project = {
	name: "NeonFrames",
	targets: [{ ...Target.iosApp("NeonFrames", "app.ms"), infoPlist: [plistBoolean("CADisableMinimumFrameDurationOnPhone", true)] }],
	plugins: [bundlePrefix("dev.neon")],
};
