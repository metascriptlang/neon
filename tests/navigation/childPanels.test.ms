import { Accessor } from "../../src/core/signal";
import { onCleanup } from "../../src/core/cleanup";
import { createEffect } from "../../src/core/effect";
import { createRoot } from "../../src/core/owner";
import { Dispose } from "../../src/core/types";
import { NavigationChild } from "../../src/navigation/children";
import {
	ChildPanels,
	ChildPanelsMode,
	Panels,
	createChildPanels,
} from "../../src/navigation/childPanels";

interface Component {
	config: int32;
	active: Accessor<boolean>;
	destroyed: boolean;
}

let created: int32 = 0;

function component(configuration: Accessor<int32>, active: Accessor<boolean>): Component {
	const made: Component = { config: configuration(), active, destroyed: false };
	created += 1;
	onCleanup((): void => { made.destroyed = true; });
	return made;
}

function key(configuration: int32): string {
	return configuration.toString();
}

function panelsOf(
	main: int32,
	details: int32 | null,
	extra: int32 | null,
	mode: ChildPanelsMode,
): Panels<int32, int32, int32> {
	return { main, details, extra, mode };
}

function makePanels(
	initial: Panels<int32, int32, int32>,
): ChildPanels<int32, Component, int32, Component, int32, Component> {
	created = 0;
	return createChildPanels<int32, Component, int32, Component, int32, Component>(
		initial,
		key,
		key,
		key,
		component,
		component,
		component,
	);
}

function child(entry: NavigationChild<int32, Component> | null): string {
	if (entry === null) { return "-"; }
	const present = entry as NavigationChild<int32, Component>;
	const config = present.configuration();
	let out = config.toString();
	if (present.instance.config !== config) { out += "!" + present.instance.config.toString(); }
	if (present.instance.destroyed) { out += "x"; }
	return out + (present.active() ? "*" : "");
}

function layout(panels: ChildPanels<int32, Component, int32, Component, int32, Component>): string {
	return child(panels.main()) + " " + child(panels.details()) + " " + child(panels.extra()) +
		" " + panels.mode().toString();
}

function optional(value: int32 | null): string {
	return value === null ? "-" : (value as int32).toString();
}

function described(panels: Panels<int32, int32, int32>): string {
	return panels.main.toString() + " " + optional(panels.details) + " " +
		optional(panels.extra) + " " + panels.mode.toString();
}

function navigated(from: Panels<int32, int32, int32>, to: Panels<int32, int32, int32>): string {
	const panels = makePanels(from);
	panels.navigate((current: Panels<int32, int32, int32>): Panels<int32, int32, int32> => to);
	const result = layout(panels);
	panels.dispose();
	return result;
}

function failure(run: () => void): string {
	try { run(); } catch (error) { return error.message; }
	return "";
}

const MODES: ChildPanelsMode[] = [
	ChildPanelsMode.Single,
	ChildPanelsMode.Dual,
	ChildPanelsMode.Triple,
];

test "each mode activates the panels Decompose resumes" {
	const mainOnly = ["1* - - Single", "1* - - Dual", "1* - - Triple"];
	const withDetails = ["1 2* - Single", "1* 2* - Dual", "1* 2* - Triple"];
	const withExtra = ["1 - 3* Single", "1* - 3* Dual", "1* - 3* Triple"];
	const all = ["1 2 3* Single", "1* 2 3* Dual", "1* 2* 3* Triple"];
	for (let i = 0; i < MODES.length; i += 1) {
		const mode = MODES[i];
		const cases: Panels<int32, int32, int32>[] = [
			panelsOf(1, null, null, mode),
			panelsOf(1, 2, null, mode),
			panelsOf(1, null, 3, mode),
			panelsOf(1, 2, 3, mode),
		];
		const wanted = [mainOnly[i], withDetails[i], withExtra[i], all[i]];
		for (let c = 0; c < cases.length; c += 1) {
			const panels = makePanels(cases[c]);
			assert layout(panels) === wanted[c], layout(panels);
			panels.dispose();
		}
	}
}

test "navigate activates details, extra or both over main in every mode" {
	const details = ["1 2* - Single", "1* 2* - Dual", "1* 2* - Triple"];
	const extra = ["1 - 2* Single", "1* - 2* Dual", "1* - 2* Triple"];
	const all = ["1 2 3* Single", "1* 2 3* Dual", "1* 2* 3* Triple"];
	for (let i = 0; i < MODES.length; i += 1) {
		const mode = MODES[i];
		const main = panelsOf(1, null, null, mode);
		let shown = navigated(main, panelsOf(1, 2, null, mode));
		assert shown === details[i], shown;
		shown = navigated(main, panelsOf(1, null, 2, mode));
		assert shown === extra[i], shown;
		shown = navigated(main, panelsOf(1, 2, 3, mode));
		assert shown === all[i], shown;
		shown = navigated(panelsOf(1, 2, null, mode), panelsOf(1, 2, 3, mode));
		assert shown === all[i], shown;
		shown = navigated(panelsOf(1, null, 3, mode), panelsOf(1, 2, 3, mode));
		assert shown === all[i], shown;
	}
}

test "navigate replaces a panel, disposing the old one and keeping the others, in every mode" {
	const main = ["11 2 3* Single", "11* 2 3* Dual", "11* 2* 3* Triple"];
	const details = ["1 22 3* Single", "1* 22 3* Dual", "1* 22* 3* Triple"];
	const extra = ["1 2 33* Single", "1* 2 33* Dual", "1* 2* 33* Triple"];
	for (let i = 0; i < MODES.length; i += 1) {
		const mode = MODES[i];
		const panels = makePanels(panelsOf(1, 2, 3, mode));
		const oldMain = panels.main().instance;
		const oldDetails = (panels.details() as NavigationChild<int32, Component>).instance;
		const oldExtra = (panels.extra() as NavigationChild<int32, Component>).instance;
		panels.navigate((current: Panels<int32, int32, int32>): Panels<int32, int32, int32> => {
			return panelsOf(11, current.details, current.extra, current.mode);
		});
		assert layout(panels) === main[i], layout(panels);
		assert oldMain.destroyed && !oldDetails.destroyed && !oldExtra.destroyed;
		panels.navigate((current: Panels<int32, int32, int32>): Panels<int32, int32, int32> => {
			return panelsOf(1, 22, current.extra, current.mode);
		});
		assert layout(panels) === details[i], layout(panels);
		assert oldDetails.destroyed && !oldExtra.destroyed;
		panels.navigate((current: Panels<int32, int32, int32>): Panels<int32, int32, int32> => {
			return panelsOf(1, 2, 33, current.mode);
		});
		assert layout(panels) === extra[i], layout(panels);
		assert oldExtra.destroyed;
		panels.dispose();
	}
}

test "navigateTo, navigateToDetails and navigateToExtra set a level and the levels below it" {
	const panels = makePanels(panelsOf(1, 2, 3, ChildPanelsMode.Single));
	panels.navigateTo(11, 22, 33);
	assert described(panels.panels()) === "11 22 33 Single", described(panels.panels());
	panels.navigateToDetails(2, 3);
	assert described(panels.panels()) === "11 2 3 Single", described(panels.panels());
	panels.navigateToExtra(null);
	assert described(panels.panels()) === "11 2 - Single", described(panels.panels());
	panels.navigateToDetails(null, 3);
	assert described(panels.panels()) === "11 - 3 Single", described(panels.panels());
	panels.dispose();
}

test "activate and dismiss change one panel and keep the rest" {
	const panels = makePanels(panelsOf(1, 2, 3, ChildPanelsMode.Single));
	panels.activateMain(11);
	assert described(panels.panels()) === "11 2 3 Single", described(panels.panels());
	panels.activateDetails(22);
	assert described(panels.panels()) === "11 22 3 Single", described(panels.panels());
	panels.activateExtra(33);
	assert described(panels.panels()) === "11 22 33 Single", described(panels.panels());
	panels.dismissDetails();
	assert described(panels.panels()) === "11 - 33 Single", described(panels.panels());
	panels.dismissDetails();
	assert described(panels.panels()) === "11 - 33 Single", "dismissing nothing changes nothing";
	panels.dismissExtra();
	assert described(panels.panels()) === "11 - - Single", described(panels.panels());
	panels.dismissExtra();
	assert layout(panels) === "11* - - Single", layout(panels);
	panels.dispose();
}

test "pop dismisses extra, then details, and reports when nothing is left" {
	const panels = makePanels(panelsOf(1, 2, 3, ChildPanelsMode.Dual));
	assert panels.pop();
	assert described(panels.panels()) === "1 2 - Dual", described(panels.panels());
	assert panels.pop();
	assert described(panels.panels()) === "1 - - Dual", described(panels.panels());
	assert !panels.pop(), "main alone has nothing to pop";
	assert described(panels.panels()) === "1 - - Dual", described(panels.panels());
	panels.dispose();
	const extraOnly = makePanels(panelsOf(1, null, 3, ChildPanelsMode.Single));
	assert extraOnly.pop();
	assert described(extraOnly.panels()) === "1 - - Single", described(extraOnly.panels());
	extraOnly.dispose();
}

test "setMode changes which panels are active and keeps every instance" {
	const panels = makePanels(panelsOf(1, 2, 3, ChildPanelsMode.Single));
	const main = panels.main().instance;
	assert !main.active(), "single mode with details shows only the top panel";
	panels.setMode(ChildPanelsMode.Dual);
	assert described(panels.panels()) === "1 2 3 Dual", described(panels.panels());
	assert layout(panels) === "1* 2 3* Dual", layout(panels);
	assert main.active() && panels.main().instance === main;
	panels.setMode(ChildPanelsMode.Triple);
	assert layout(panels) === "1* 2* 3* Triple", layout(panels);
	assert created === 3, "a mode change creates nothing: " + created.toString();
	panels.dispose();
}

test "back in single mode dismisses the top panel and is not handled otherwise" {
	const single = ["1* - - Single", "1* - - Single", "1* - - Single", "1 2* - Single"];
	const handled = [false, true, true, true];
	for (let i = 0; i < MODES.length; i += 1) {
		const mode = MODES[i];
		const cases: Panels<int32, int32, int32>[] = [
			panelsOf(1, null, null, mode),
			panelsOf(1, 2, null, mode),
			panelsOf(1, null, 3, mode),
			panelsOf(1, 2, 3, mode),
		];
		for (let c = 0; c < cases.length; c += 1) {
			const panels = makePanels(cases[c]);
			const before = layout(panels);
			const back = panels.back();
			if (mode === ChildPanelsMode.Single) {
				assert back === handled[c], before;
				assert layout(panels) === single[c], before + " -> " + layout(panels);
			} else {
				assert !back, before;
				assert layout(panels) === before, before + " -> " + layout(panels);
			}
			panels.dispose();
		}
	}
}

test "a panel keyed apart from its configuration keeps its instance and sees the new one" {
	const panels = createChildPanels<int32, Component, int32, Component, int32, Component>(
		panelsOf(1, 2, null, ChildPanelsMode.Dual),
		key,
		(configuration: int32): string => "details",
		key,
		component,
		component,
		component,
	);
	const details = panels.details() as NavigationChild<int32, Component>;
	const mainConfiguration = panels.main().configuration;
	let mainRuns: int32 = 0;
	const stop = createEffect((): void => {
		mainConfiguration();
		mainRuns += 1;
	});
	assert mainRuns === 1, mainRuns.toString();
	panels.activateDetails(22);
	stop();
	const kept = panels.details() as NavigationChild<int32, Component>;
	assert kept.instance === details.instance, "the same details key keeps the instance";
	assert kept.configuration() === 22, kept.configuration().toString();
	assert mainRuns === 1, "main is not notified of a details change: " + mainRuns.toString();
	panels.dispose();
}

test "panels of different kinds with the same key are different children" {
	const panels = makePanels(panelsOf(1, 1, 1, ChildPanelsMode.Triple));
	assert layout(panels) === "1* 1* 1* Triple", layout(panels);
	assert created === 3, created.toString();
	panels.dispose();
}

test "an empty key fails loudly and changes nothing" {
	const panels = createChildPanels<int32, Component, int32, Component, int32, Component>(
		panelsOf(1, null, null, ChildPanelsMode.Single),
		key,
		(configuration: int32): string => configuration === 0 ? "" : configuration.toString(),
		key,
		component,
		component,
		component,
	);
	const empty = failure((): void => { panels.activateDetails(0); });
	assert empty === "navigation: empty child key", empty;
	assert layout(panels) === "1* - - Single", layout(panels);
	panels.dispose();
}

test "the owner of the panels disposes every panel" {
	const instances: Component[] = [];
	createRoot((dispose: Dispose): void => {
		const panels = makePanels(panelsOf(1, 2, 3, ChildPanelsMode.Triple));
		instances.push(panels.main().instance);
		instances.push((panels.details() as NavigationChild<int32, Component>).instance);
		instances.push((panels.extra() as NavigationChild<int32, Component>).instance);
		dispose();
	});
	assert instances.length === 3;
	for (const instance of instances) { assert instance.destroyed; }
}
