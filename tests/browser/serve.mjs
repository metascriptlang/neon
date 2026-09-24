import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { extname, join, normalize, resolve } from "node:path";

const [, , root, port] = process.argv;
const base = resolve(root);
const types = { ".html": "text/html", ".js": "text/javascript", ".mjs": "text/javascript", ".map": "application/json" };

createServer(async (req, res) => {
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
}).listen(Number(port), "127.0.0.1");
