import { domHost } from "../../src/platform/browser/dom";
import { Host, HostNode } from "../../src/render/hostTypes";
import { Dispose } from "../../src/core/types";
import { render } from "../../src/render/host";
import { element } from "../../src/macros/ui/element";
import { View } from "../../src/components/primitives";
import { accessor } from "../../src/core/signal";
import {
	ScrollPosition,
	useWindowScrollPosition,
	useWindowScrollRange,
} from "../../src/api/pageScroll";
import { sleepAsync } from "std/core/promise";

extern function reach(code: cstring): number from "Number((0, eval)(#))";

extern class HTMLElement {
	extern appendChild(child: HTMLElement): void;
	extern remove(): void;
}

extern class document {
	static body: HTMLElement;
	static extern createElement(tag: cstring): HTMLElement;
}

function pageRangeY(): number {
	return reach("document.documentElement.scrollHeight - document.documentElement.clientHeight");
}

function pageRangeX(): number {
	return reach("document.documentElement.scrollWidth - document.documentElement.clientWidth");
}

function pair(at: ScrollPosition): string {
	return at.x.toString() + "," + at.y.toString();
}

function mountPoint(): HTMLElement {
	const mount = document.createElement("div");
	document.body.appendChild(mount);
	return mount;
}

test "the page's scroll offset and range reach the accessors and a derived share follows" {
	const position = useWindowScrollPosition();
	const range = useWindowScrollRange();
	const share = accessor((): number => range().y > 0 ? position().y / range().y : 0);
	const mount = mountPoint();
	const page = element(<View style={{ height: 3000, width: 2500 }} />);
	const dispose = render(page, domHost(), mount as unknown as HostNode);
	await sleepAsync(100);
	assert pageRangeY() > 2000, "the page can scroll: " + pageRangeY().toString();
	assert range().y === pageRangeY(), "range " + range().y.toString();
	assert range().x === pageRangeX() && range().x > 1000, "x range " + range().x.toString();
	assert pair(position()) === "0,0" && share() === 0, "at the top";
	reach("scrollTo(250, 400)");
	await sleepAsync(100);
	assert pair(position()) === "250,400", "offset: " + pair(position());
	assert share() === 400 / range().y, "share: " + share().toString();
	reach("scrollTo(0, 1e9)");
	await sleepAsync(100);
	assert pair(position()) === "0," + range().y.toString(), "the end: " + pair(position());
	assert share() === 1, "share at the end: " + share().toString();
	reach("scrollTo(0, 0)");
	await sleepAsync(100);
	assert share() === 0, "back at the top: " + share().toString();
	dispose();
	mount.remove();
}

function grow(host: Host, mount: HTMLElement, height: number): Dispose {
	const content = element(<View style={{ height: height }} />);
	return render(content, host, mount as unknown as HostNode);
}

test "the range follows content that grows and a resize event" {
	const host = domHost();
	const range = useWindowScrollRange();
	const mount = mountPoint();
	const first = grow(host, mount, 3000);
	await sleepAsync(100);
	const before = range().y;
	assert before === pageRangeY() && before > 2000, "first range: " + before.toString();
	const second = grow(host, mount, 1000);
	await sleepAsync(100);
	assert range().y === before + 1000, "seen by the observer: " + range().y.toString();
	const third = grow(host, mount, 500);
	reach("dispatchEvent(new Event('resize'))");
	assert range().y === before + 1500, "seen by the resize listener: " + range().y.toString();
	third();
	second();
	first();
	mount.remove();
	await sleepAsync(100);
	assert range().y === pageRangeY(), "back to the page's own range: " + range().y.toString();
	assert range().y < before, "shrinks again";
}
