import { createSignal } from "../../src/core/signal";
import { flush } from "../../src/core/runtime";
import { Dimensions } from "../../src/api/dimensions";
import { HostNode } from "../../src/render/hostTypes";
import { ElementHandle } from "../../src/render/measure";
import { render } from "../../src/render/host";
import { domHost, documentBody } from "../../src/platform/browser/dom";
import { element } from "../../src/macros/ui/element";
import { View, Text } from "../../src/components/primitives";
import { Dialog } from "../../src/components/dialog";
import { BottomSheet } from "../../src/components/bottomSheet";
import { Snackbar } from "../../src/components/snackbar";
import { Toast, ToastHost } from "../../src/components/toast";
import { Portal } from "../../src/render/portal";
import { sleepAsync } from "std/core/promise";

extern class HTMLElement {}
extern class Rectangle {
	top: float64;
	width: float64;
	height: float64;
	left: float64;
	right: float64;
	bottom: float64;
}

extern function alertNode(label: cstring): HTMLElement from "document.querySelector('[aria-label=\"' + # + '\"]')";
extern function hasAlert(label: cstring): boolean from "document.querySelector('[aria-label=\"' + # + '\"]') !== null";
extern function parent(node: HTMLElement): HTMLElement from "#.parentElement";
extern function rect(node: HTMLElement): Rectangle from "#.getBoundingClientRect()";
extern function isBody(node: HTMLElement): boolean from "# === document.body";
extern function contains(root: HTMLElement, node: HTMLElement): boolean from "#.contains(#)";
extern function remove(node: HTMLElement): void from "#.remove()";

extern function bodyCss(): string from "(() => document.body.style.cssText)()";
extern function setBodyCss(css: string): void from "(document.body.style.cssText = #)";
extern function prepareScroll(positioned: boolean): void from
	"(document.body.style.cssText = 'min-height:5000px;margin:0;position:' + (# ? 'relative' : 'static'))";
extern function scrollPage(y: float64): void from "window.scrollTo(0, #)";
extern function scrollY(): float64 from "(() => window.scrollY)()";
extern function positionOf(node: HTMLElement): string from "getComputedStyle(#).position";

function near(a: float64, b: float64): boolean { return Math.abs(a - b) < 0.01; }

test "screen overlays use viewport geometry outside a clipped app and retain reactive dismissal" {
	const [open, setOpen] = createSignal(true);
	const roots: HostNode[] = [];
	const dispose = render(element(<View ref={(h: ElementHandle): void => { roots.push(h.node); }} style={{ width: 24, height: 24, overflow: "hidden", position: "relative" }}>
		<Dialog visible={open()} title="Portal dialog"><Text>Dialog body</Text></Dialog>
		<BottomSheet visible={open()} height={240} accessibilityLabel="Portal sheet"><Text>Sheet body</Text></BottomSheet>
		<Snackbar visible={open()} message="Portal snackbar" />
		<ToastHost />
	</View>), domHost(), documentBody());
	flush();
	Toast.show({ text1: "Portal toast", autoHide: false });
	flush();
	const viewport = Dimensions.get("window");
	const app = roots[0] as unknown as HTMLElement;
	const dialog = alertNode("Portal dialog");
	const dialogLayer = parent(dialog);
	assert isBody(parent(dialogLayer)) && !contains(app, dialog);
	const bounds = rect(dialogLayer);
	assert near(bounds.width, viewport.width) && near(bounds.height, viewport.height);
	const sheet = alertNode("Portal sheet");
	assert isBody(parent(parent(sheet))) && !contains(app, sheet);
	assert near(rect(sheet).bottom, viewport.height) && near(rect(sheet).height, 240);
	const snackbar = alertNode("Portal snackbar");
	assert isBody(parent(snackbar)) && !contains(app, snackbar);
	const bar = rect(snackbar);
	assert near(bar.left, 8) && near(bar.right, viewport.width - 8) && near(bar.bottom, viewport.height - 8);
	const toast = alertNode("Portal toast");
	assert isBody(parent(parent(toast))) && !contains(app, toast);
	assert near(rect(parent(toast)).bottom, viewport.height - 40);
	setOpen(false);
	flush();
	Toast.hide();
	flush();
	assert !hasAlert("Portal dialog") && !hasAlert("Portal sheet") && !hasAlert("Portal snackbar") && !hasAlert("Portal toast");
	setOpen(true);
	flush();
	Toast.show({ text1: "Portal toast", autoHide: false });
	flush();
	dispose();
	flush();
	assert !hasAlert("Portal dialog") && !hasAlert("Portal sheet") && !hasAlert("Portal snackbar") && !hasAlert("Portal toast");
	Toast.hide();
	flush();
	remove(app);
}

test "a screen-level Dialog on the body survives hide show and owner cleanup without double removal" {
	const [open, setOpen] = createSignal(true);
	const dispose = render(element(<Dialog visible={open()} title="Same-root dialog" />), domHost(), documentBody());
	flush();
	assert hasAlert("Same-root dialog");
	setOpen(false);
	flush();
	assert !hasAlert("Same-root dialog");
	setOpen(true);
	flush();
	assert hasAlert("Same-root dialog");
	dispose();
	flush();
	assert !hasAlert("Same-root dialog");
}

test "screen overlays stay viewport anchored across document scroll and positioned body" {
	const css = bodyCss();
	try {
		for (const positioned of [false, true]) {
			prepareScroll(positioned);
			const [open, setOpen] = createSignal(false);
			const dispose = render(element(<View style={{ width: 24, height: 24, overflow: "hidden" }}>
				<Dialog visible={open()} title="Scrolled dialog" />
				<BottomSheet visible={open()} height={240} accessibilityLabel="Scrolled sheet" />
				<Snackbar visible={open()} message="Scrolled snackbar" />
				<ToastHost />
				<Portal style={{ position: "absolute", left: 20, top: 40 }}>
					<Text accessibilityLabel="Generic portal">Generic</Text>
				</Portal>
			</View>), domHost(), documentBody());
			flush();
			try {
				scrollPage(200);
				await sleepAsync(30);
				assert scrollY() > 100, "document scroll fixture is active before show";
				setOpen(true);
				flush();
				Toast.show({ text1: "Scrolled toast", autoHide: false });
				flush();
				for (const offset of [200, 500]) {
					scrollPage(offset);
					await sleepAsync(30);
					assert near(scrollY(), offset);
					const viewport = Dimensions.get("window");
					const dialog = rect(parent(alertNode("Scrolled dialog")));
					assert near(dialog.top, 0) && near(dialog.left, 0), "scrim starts at viewport";
					assert near(dialog.width, viewport.width) && near(dialog.height, viewport.height);
					const sheet = rect(alertNode("Scrolled sheet"));
					assert near(sheet.bottom, viewport.height) && near(sheet.height, 240);
					const bar = rect(alertNode("Scrolled snackbar"));
					assert near(bar.left, 8) && near(bar.right, viewport.width - 8);
					assert near(bar.bottom, viewport.height - 8);
					assert near(rect(parent(alertNode("Scrolled toast"))).bottom, viewport.height - 40);
					assert positionOf(parent(alertNode("Generic portal"))) === "absolute",
						"generic Portal must not become a fixed screen layer";
				}
				setOpen(false);
				flush();
				Toast.hide();
				flush();
				assert !hasAlert("Scrolled dialog") && !hasAlert("Scrolled sheet");
				assert !hasAlert("Scrolled snackbar") && !hasAlert("Scrolled toast");
				setOpen(true);
				flush();
				Toast.show({ text1: "Scrolled toast", autoHide: false });
				flush();
			} finally {
				dispose();
				flush();
				Toast.hide();
				flush();
			}
			assert !hasAlert("Scrolled dialog") && !hasAlert("Scrolled sheet");
			assert !hasAlert("Scrolled snackbar") && !hasAlert("Scrolled toast");
		}
	} finally {
		setBodyCss(css);
		flush();
		scrollPage(0);
	}
}

test "explicit Snackbar and Toast user position wins over default screen presentation" {
	const [override, setOverride] = createSignal(true);
	const dispose = render(element(<View>
		<Snackbar visible={true} message="Custom snackbar"
			style={{ position: override() ? "absolute" : null }} />
		<ToastHost style={{ position: override() ? "absolute" : null }} />
	</View>), domHost(), documentBody());
	flush();
	try {
		Toast.show({ text1: "Custom toast", autoHide: false });
		flush();
		assert positionOf(alertNode("Custom snackbar")) === "absolute";
		assert positionOf(parent(alertNode("Custom toast"))) === "absolute";
		setOverride(false);
		flush();
		assert positionOf(alertNode("Custom snackbar")) === "fixed";
		assert positionOf(parent(alertNode("Custom toast"))) === "fixed";
		setOverride(true);
		flush();
		assert positionOf(alertNode("Custom snackbar")) === "absolute";
		assert positionOf(parent(alertNode("Custom toast"))) === "absolute";
	} finally {
		dispose();
		flush();
		Toast.hide();
		flush();
	}
}
