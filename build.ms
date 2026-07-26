// Neon Build Configuration
// MetaScript declarative build config (like vite.config.ts)

import { BuildConfig } from "std/build";

const config: BuildConfig = {
	fmt: { useTabs: true },
};

// export default defineConfig({
// 	root: "src/index.ms",
// 	fmt: {
// 		useTabs: true,
// 	},
// 	build: {
// 		targets: [
// 			{ target: "native", outDir: "build/c" },
// 			{ target: "js", outDir: "build/js" },
// 		],
// 	},
// });
