import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { extname, join, normalize, resolve } from "node:path";

const [, , root, port] = process.argv;
const base = resolve(root);
const types = { ".html": "text/html", ".js": "text/javascript", ".mjs": "text/javascript", ".map": "application/json" };

const server = createServer(async (req, res) => {
	const path = normalize(join(base, decodeURIComponent(new URL(req.url, "http://x").pathname)));
	if (!path.startsWith(base)) {
		res.writeHead(403).end();
		return;
	}
	try {
		const body = await readFile(path);
		res.writeHead(200, { "content-type": types[extname(path)] ?? "application/octet-stream" }).end(body);
	} catch {
		res.writeHead(404).end();
	}
});
server.on("error", (e) => {
	console.error(`serve.mjs: cannot listen on 127.0.0.1:${port}: ${e.code ?? e.message}`);
	process.exit(1);
});
server.listen(Number(port ?? 0), "127.0.0.1", () => console.log(server.address().port));
