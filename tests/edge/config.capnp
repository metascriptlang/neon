using Workerd = import "/workerd/workerd.capnp";

const config :Workerd.Config = (
	services = [(name = "main", worker = .pages), (name = "site", worker = .site)],
	sockets = [
		(name = "http", address = "127.0.0.1:0", http = (), service = "main"),
		(name = "site", address = "127.0.0.1:0", http = (), service = "site"),
	],
);

const pages :Workerd.Worker = (
	modules = [
		(name = "worker.js", esModule = embed "worker.js"),
		(name = "out/pages.js", esModule = embed "out/pages.js"),
	],
	compatibilityDate = "2026-10-01",
);

const site :Workerd.Worker = (
	modules = [
		(name = "siteWorker.js", esModule = embed "siteWorker.js"),
		(name = "out/site.js", esModule = embed "out/site.js"),
		(name = "out/siteClient.js", text = embed "out/siteClient.js"),
	],
	compatibilityDate = "2026-10-01",
);
