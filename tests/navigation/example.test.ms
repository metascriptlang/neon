import { HostNode, MockNode, mockNode, mockHost, render, fireEventWith } from "../../src/render/host";
import { neonEvent } from "../../src/render/event";
import { dispatchHardwareBackPress } from "../../src/api/backHandler";
import { publishUrl } from "../../src/api/linking";
import { NavigationContainerRef } from "../../src/navigation/index";
import { NavigationDemo, navigationRef } from "../../examples/components/navigation";
import { findLabel, press, visibleText } from "./navHarness";

function type(root: MockNode, label: string, text: string): void {
	const node = findLabel(root, label);
	if (node === null) { throw new Error("no field labelled " + label); }
	const e = neonEvent("input");
	e.value = text;
	fireEventWith(node as MockNode, "onChangeText", e);
	fireEventWith(node as MockNode, "onInput", e);
}

test "the navigation example walks list, detail, edit, tabs, drawer and a deep link" {
	const root: MockNode = mockNode("root");
	const dispose = render(NavigationDemo(), mockHost(), root as unknown as HostNode);
	assert navigationRef.currentPath() === "Main>Home>List", navigationRef.currentPath();
	press(root, "Increment home");
	press(root, "Open Void shader");
	assert navigationRef.currentPath() === "Main>Home>Detail", navigationRef.currentPath();
	assert visibleText(root).indexOf("Void shader|Item number 2") >= 0, visibleText(root);
	press(root, "Edit item");
	type(root, "Item name", "Void renderer");
	press(root, "Save");
	assert navigationRef.currentPath() === "Main>Home>Detail", navigationRef.currentPath();
	assert visibleText(root).indexOf("Void renderer|Item number 2") >= 0, visibleText(root);
	press(root, "Back");
	assert visibleText(root).indexOf("Home taps 1") >= 0, "list state kept: " + visibleText(root);
	assert visibleText(root).indexOf("Void renderer") >= 0, visibleText(root);

	press(root, "Search");
	press(root, "Increment search");
	press(root, "Add badge");
	assert visibleText(root).indexOf("Search|1") >= 0, "badge: " + visibleText(root);
	press(root, "Profile");
	press(root, "Increment profile");
	press(root, "Search");
	assert visibleText(root).indexOf("Searches 1") >= 0, visibleText(root);

	press(root, "Home");
	press(root, "Show navigation menu");
	press(root, "Settings");
	assert navigationRef.currentPath() === "Settings", navigationRef.currentPath();
	assert dispatchHardwareBackPress();
	assert navigationRef.currentPath() === "Main>Home>List", navigationRef.currentPath();

	publishUrl("neonnav://items/4");
	assert visibleText(root).indexOf("Ion window|Item number 4") >= 0, visibleText(root);
	dispose();
}
