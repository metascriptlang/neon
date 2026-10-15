import { createSignal } from "../../src/core/signal";
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

extern class HTMLElement {}
extern class Rectangle {
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
	Toast.show({ text1: "Portal toast", autoHide: false });
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
	Toast.hide();
	assert !hasAlert("Portal dialog") && !hasAlert("Portal sheet") && !hasAlert("Portal snackbar") && !hasAlert("Portal toast");
	setOpen(true);
	Toast.show({ text1: "Portal toast", autoHide: false });
	dispose();
	assert !hasAlert("Portal dialog") && !hasAlert("Portal sheet") && !hasAlert("Portal snackbar") && !hasAlert("Portal toast");
	Toast.hide();
	remove(app);
}

test "a screen-level Dialog on the body survives hide show and owner cleanup without double removal" {
	const [open, setOpen] = createSignal(true);
	const dispose = render(element(<Dialog visible={open()} title="Same-root dialog" />), domHost(), documentBody());
	assert hasAlert("Same-root dialog");
	setOpen(false);
	assert !hasAlert("Same-root dialog");
	setOpen(true);
	assert hasAlert("Same-root dialog");
	dispose();
	assert !hasAlert("Same-root dialog");
}
