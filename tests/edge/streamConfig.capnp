using Workerd = import "/workerd/workerd.capnp";

const config :Workerd.Config = (
	services = [
		(name = "stream", worker = .stream),
		(name = "internet", network = (allow = ["local"])),
	],
	sockets = [(name = "http", address = "127.0.0.1:0", http = (), service = "stream")],
);

const stream :Workerd.Worker = (
	modules = [
		(name = "streamWorker.js", esModule = embed "streamWorker.js"),
		(name = "out/streamPages.js", esModule = embed "out/streamPages.js"),
	],
	compatibilityDate = "2026-10-01",
);
