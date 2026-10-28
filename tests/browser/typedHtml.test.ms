import { domHost, documentBody } from "../../src/platform/browser/dom";
import { render } from "../../src/render/host";
import { createSignal } from "../../src/core/signal";
import { flush } from "../../src/core/runtime";

test "a ref receives the element's DOM class and typed attribute values reach the DOM" {
	let canvasWidth: number = 0;
	let canvasTag = "";
	let input: HTMLInputElement | null = null;
	let cell: HTMLTableCellElement | null = null;
	const [locked, setLocked] = createSignal(true);
	const span = 2;
	const dispose = render(
		<div>
			<canvas width={40} ref={(c: HTMLCanvasElement): void => { canvasWidth = c.width; canvasTag = c.tagName; }} />
			<input disabled={locked()} tabindex={span} spellcheck={false} ref={(i: HTMLInputElement): void => { input = i; }} />
			<table><tbody><tr><td colspan={span} ref={(t: HTMLTableCellElement): void => { cell = t; }}>a</td></tr></tbody></table>
		</div>,
		domHost(),
		documentBody(),
	);
	assert canvasWidth === 40 && canvasTag === "CANVAS", "canvas ref: " + canvasTag + " " + canvasWidth.toString();
	const field = input as HTMLInputElement;
	assert field.disabled && field.getAttribute("disabled") === "", "disabled present";
	assert field.tabIndex === 2 && field.getAttribute("spellcheck") === "false", "tabindex and spellcheck";
	assert (cell as HTMLTableCellElement).colSpan === 2, "colspan";
	setLocked(false);
	flush();
	assert !field.disabled && !field.hasAttribute("disabled"), "a false boolean removes the attribute";
	dispose();
}
