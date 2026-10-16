import { NeonEvent } from "../../src/render/event";
import { NeonNode } from "../../src/render/hostTypes";
import { renderToMarkup } from "../../src/render/ssr";
import {
	clampedApp,
	docsAtStart,
	headPageAtStart,
	linesApp,
	marksApp,
	plainTextareaApp,
	primitivesApp,
	scrollApp,
	scrollViewApp,
	switchAppOn,
	switchesApp,
	textareaApp,
	textareasApp,
} from "./servedApps";

function served(name: string, app: NeonNode): string {
	return JSON.stringify(name) + ":" + JSON.stringify(renderToMarkup(app));
}

function main(): void {
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
	];
	console.log("{" + pages.join(",") + "}");
}
main();
