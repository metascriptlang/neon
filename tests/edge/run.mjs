import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createServer } from "node:net";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const workerd = process.argv[2];
const port = await new Promise((found) => {
	const probe = createServer().listen(0, "127.0.0.1", () => {
		const free = probe.address().port;
		probe.close(() => found(free));
	});
});
const origin = `http://127.0.0.1:${port}`;
const server = spawn(workerd, ["serve", join(here, "config.capnp"), "--socket-addr", `http=127.0.0.1:${port}`], {
	stdio: ["ignore", "inherit", "inherit"],
});

async function get(path) {
	const response = await fetch(origin + path);
	return { status: response.status, body: await response.text() };
}

async function started() {
	for (let attempt = 0; attempt < 100; attempt += 1) {
		if (server.exitCode !== null) { throw new Error(`workerd exited with ${server.exitCode}`); }
		try { return await get("/"); } catch { await new Promise((wake) => setTimeout(wake, 50)); }
	}
	throw new Error(`workerd did not answer on ${origin}`);
}

try {
	const home = await started();
	const guide = await get("/guide");
	assert.equal(home.status, 200);
	assert.match(home.body, /home page/);
	assert.match(home.body, /padding:24px/);
	assert.doesNotMatch(home.body, /margin:12px/, "the first page carries the second page's rule");
	assert.match(guide.body, /guide page/);
	assert.match(guide.body, /margin:12px/);
	assert.doesNotMatch(guide.body, /padding:24px/, "the second page carries the first page's rule");
	assert.match(guide.body, /white-space:pre-wrap/, "the second page lost the base rule");

	const broken = await get("/broken");
	assert.equal(broken.status, 500);
	assert.deepEqual(await get("/"), home, "a page changed after other requests");
	assert.deepEqual(await get("/guide"), guide, "a page changed after a failed request");
	console.log("PASS: workerd answers each path with its own page and rules, with no browser globals");
} finally {
	server.kill();
}
