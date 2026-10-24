import { NeonEvent } from "../../src/render/event";
import { NeonNode } from "../../src/render/hostTypes";
import { renderToMarkup, renderToStream, SsrMarkup } from "../../src/render/ssr";
import { sleepAsync } from "std/core/promise";
import { asyncPage, Note } from "./asyncPage";
import {
	clampedApp,
	docsAtStart,
	headPageAtStart,
	imagesAtStart,
	linesApp,
	marksApp,
	mediaAtStart,
	modalAtStart,
	plainTextareaApp,
	primitivesApp,
	scrollApp,
	scrollViewApp,
	svgAtStart,
	switchAppOn,
	switchesApp,
	textareaApp,
	textareasApp,
} from "./servedApps";

function served(name: string, app: NeonNode): string {
	return JSON.stringify(name) + ":" + JSON.stringify(renderToMarkup(app));
}

async function fromServer(n: int32): Promise<Note> {
	await sleepAsync(3);
	return { text: "server says", n: n };
}

async function main(): Promise<void> {
	const streamed: SsrMarkup = await renderToStream(asyncPage(fromServer));
	const pages: string[] = [
		served("docs", docsAtStart()),
		served("scroll", scrollApp((e: NeonEvent): void => {})),
		served("clamped", clampedApp()),
		served("switch", switchAppOn()),
		served("textarea", textareaApp((t: string): void => {})),
		served("plainTextarea", plainTextareaApp()),
		served("headPage", headPageAtStart()),
		served("primitives", primitivesApp()),
		served("marks", marksApp()),
		served("scrollView", scrollViewApp()),
		served("lines", linesApp()),
		served("switches", switchesApp()),
		served("textareas", textareasApp()),
		served("images", imagesAtStart()),
		served("svg", svgAtStart()),
		served("modal", modalAtStart()),
		served("media", mediaAtStart()),
		JSON.stringify("async") + ":" + JSON.stringify(streamed),
	];
	console.log("{" + pages.join(",") + "}");
}
main();
