import { resolve } from "node:path";
import metascript from "vite-plugin-metascript";

const here = import.meta.dirname;
const root = resolve(process.env.REFRESH_ROOT ?? here);

export default ({ command }) => ({
	root,
	logLevel: "info",
	clearScreen: false,
	server: { port: Number(process.env.REFRESH_PORT ?? 5197), strictPort: true, fs: { allow: [resolve(here, "../..")] } },
	preview: { port: Number(process.env.REFRESH_PREVIEW_PORT ?? 5196), strictPort: true },
	build: { outDir: resolve(root, "dist"), emptyOutDir: true },
	plugins: [metascript({ entry: resolve(root, "main.ms"), compilerArgs: command === "serve" ? ["-d:refresh"] : undefined })],
});
