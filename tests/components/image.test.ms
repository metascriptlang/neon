import { createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { NeonEvent, neonEvent } from "../../src/render/event";
import { HostNode, MockNode, mockNode, mockHost, render, fireEventWith } from "../../src/render/host";
import { Image, ImageLoader } from "../../src/components/image";
import { FakeServices } from "../api/fakeServices";
import { sleepAsync } from "std/core/promise";

function attrOf(n: MockNode, name: string): string {
	for (const a of n.attrs) {
		if (a.name === name) { return a.value ?? ""; }
	}
	return "<unset>";
}

test "Image sends resizeMode repeat and blurRadius to the host" {
	const root: MockNode = mockNode("root");
	const [blur, setBlur] = createSignal(4);
	render(element(<Image source={{ uri: "https://x/a.png" }} resizeMode="repeat" blurRadius={blur()} />), mockHost(), root as unknown as HostNode);
	const image = root.children[0];
	assert attrOf(image, "resizeMode") === "repeat", "repeat";
	assert attrOf(image, "blurRadius") === "4", "blur " + attrOf(image, "blurRadius");
	setBlur(0);
	assert attrOf(image, "blurRadius") === "0", "blur cleared";
}

test "ImageLoader.getSize reports the size or the failure the services load" {
	const services = new FakeServices();
	services.install();
	let got = "";
	ImageLoader.getSize("https://x/a.png", (w: number, h: number): void => { got += `${w}x${h};`; });
	ImageLoader.getSize("https://x/missing.png", (w: number, h: number): void => { got += "wrong;"; }, (e: Error): void => { got += "failed " + e.message + ";"; });
	assert services.joined() === "imageSize https://x/a.png;imageSize https://x/missing.png", services.joined();
	services.imageDone[0](600, 240, "");
	services.imageDone[1](0, 0, "HTTP 404");
	assert got === "600x240;failed HTTP 404;", got;
}

test "ImageLoader.prefetch resolves true once the image is cached, false on failure" {
	const services = new FakeServices();
	services.install();
	let ok = "";
	const run = async (): Promise<void> => {
		const first = await ImageLoader.prefetch("https://x/a.png");
		const second = await ImageLoader.prefetch("https://x/b.png");
		ok = `${first} ${second}`;
	};
	run();
	services.imageDone[0](10, 10, "");
	await sleepAsync(40);
	services.imageDone[1](0, 0, "HTTP 500");
	await sleepAsync(40);
	assert ok === "true false", "prefetch: " + ok;
}

test "Image defaultSource shows until the source is cached, and onLoad waits for the source" {
	const services = new FakeServices();
	services.install();
	const root: MockNode = mockNode("root");
	let log = "";
	const [uri, setUri] = createSignal("https://x/photo.png");
	render(element(<Image source={{ uri: uri() }} defaultSource={{ uri: "data:placeholder" }}
		onLoad={(e: NeonEvent): void => { log += "load;"; }} onError={(e: NeonEvent): void => { log += "error " + e.value + ";"; }} />), mockHost(), root as unknown as HostNode);
	const image = root.children[0];
	const placeholder = attrOf(image, "source");
	fireEventWith(image, "onLoad", neonEvent("load"));
	const early = log;
	services.imageDone[0](800, 600, "");
	const loaded = attrOf(image, "source");
	fireEventWith(image, "onLoad", neonEvent("load"));
	setUri("https://x/broken.png");
	const back = attrOf(image, "source");
	services.imageDone[1](0, 0, "HTTP 404");
	assert placeholder === "data:placeholder" && early === "", `placeholder first, its load is not the source's: ${placeholder} ${early}`;
	assert loaded === "https://x/photo.png", "the source once cached: " + loaded;
	assert back === "data:placeholder", "a new source shows the placeholder again: " + back;
	assert log === "load;error HTTP 404;", "events: " + log;
}
