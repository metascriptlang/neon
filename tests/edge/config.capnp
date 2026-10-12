using Workerd = import "/workerd/workerd.capnp";

const config :Workerd.Config = (
	services = [(name = "main", worker = .pages)],
	sockets = [(name = "http", address = "127.0.0.1:0", http = (), service = "main")],
);

const pages :Workerd.Worker = (
	modules = [
		(name = "worker.js", esModule = embed "worker.js"),
		(name = "out/pages.js", esModule = embed "out/pages.js"),
	],
	compatibilityDate = "2026-10-01",
);
