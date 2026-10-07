import { spawn } from "node:child_process";

export function startServer(root) {
	const server = spawn("node", ["tests/browser/serve.mjs", root, process.env.NEON_BROWSER_PORT ?? "0"], { stdio: ["ignore", "pipe", "pipe"] });
	server.stderr.pipe(process.stderr);
	process.on("exit", () => server.kill());
	return new Promise((done, fail) => {
		server.stdout.once("data", (chunk) => done({ server, port: Number(String(chunk).trim()) }));
		server.once("exit", (code) => fail(new Error(`the test server exited with ${code} before listening`)));
	});
}
