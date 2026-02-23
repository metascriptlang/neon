// Neon Build Configuration
// MetaScript declarative build config (like vite.config.ts)

import { defineConfig, BuildOptions } from "std/build";

export default defineConfig({
	root: "src/index.ms",
	format: {
		tabWidth: 4,
		useTabs: true,
		semi: true,
	},
	build: {
		targets: [
			{ target: "native", outDir: "build/c" },
			{ target: "js", outDir: "build/js" },
		],
	},
});
