import { Accessor, untrack } from "../core/signal";
import { createMemo } from "../core/memo";
import { ChildNavigation, ChildState, NavigationChild, createChildren } from "./children";

export enum ChildPanelsMode {
	Single,
	Dual,
	Triple,
}

export interface Panels<MC, DC, EC> {
	main: MC;
	details: DC | null;
	extra: EC | null;
	mode: ChildPanelsMode;
}

enum PanelKind {
	Main,
	Details,
	Extra,
}

interface Panel<MC, DC, EC> {
	kind: PanelKind;
	panels: Panels<MC, DC, EC>;
}

interface PanelChild<MC, MT, DC, DT, EC, ET> {
	main: NavigationChild<MC, MT> | null;
	details: NavigationChild<DC, DT> | null;
	extra: NavigationChild<EC, ET> | null;
}

function panelKey(kind: string, key: string): string {
	if (key === "") { throw new Error("navigation: empty child key"); }
	return kind + ":" + key;
}

function panelsState<MC, DC, EC>(
	panels: Panels<MC, DC, EC>,
	mainKey: (configuration: MC) => string,
	detailsKey: (configuration: DC) => string,
	extraKey: (configuration: EC) => string,
): ChildState<Panel<MC, DC, EC>>[] {
	const details = panels.details;
	const extra = panels.extra;
	const state: ChildState<Panel<MC, DC, EC>>[] = [];
	state.push({
		key: panelKey("main", mainKey(panels.main)),
		configuration: { kind: PanelKind.Main, panels },
		active: panels.mode !== ChildPanelsMode.Single || (details === null && extra === null),
	});
	if (details !== null) {
		state.push({
			key: panelKey("details", detailsKey(details as DC)),
			configuration: { kind: PanelKind.Details, panels },
			active: panels.mode === ChildPanelsMode.Triple || extra === null,
		});
	}
	if (extra !== null) {
		state.push({
			key: panelKey("extra", extraKey(extra as EC)),
			configuration: { kind: PanelKind.Extra, panels },
			active: true,
		});
	}
	return state;
}

function panelChild<C, T>(
	key: string,
	configuration: Accessor<C>,
	active: Accessor<boolean>,
	factory: (configuration: Accessor<C>, active: Accessor<boolean>) => T,
): NavigationChild<C, T> {
	return { key, configuration, active, instance: factory(configuration, active) };
}

export class ChildPanels<MC, MT, DC, DT, EC, ET> {
	private children: ChildNavigation<Panel<MC, DC, EC>, PanelChild<MC, MT, DC, DT, EC, ET>>;
	private mainKey: (configuration: MC) => string;
	private detailsKey: (configuration: DC) => string;
	private extraKey: (configuration: EC) => string;

	constructor(
		children: ChildNavigation<Panel<MC, DC, EC>, PanelChild<MC, MT, DC, DT, EC, ET>>,
		mainKey: (configuration: MC) => string,
		detailsKey: (configuration: DC) => string,
		extraKey: (configuration: EC) => string,
	) {
		this.children = children;
		this.mainKey = mainKey;
		this.detailsKey = detailsKey;
		this.extraKey = extraKey;
	}

	main(): NavigationChild<MC, MT> {
		return this.children.children()[0].instance.main as NavigationChild<MC, MT>;
	}

	details(): NavigationChild<DC, DT> | null {
		for (const child of this.children.children()) {
			if (child.instance.details !== null) { return child.instance.details; }
		}
		return null;
	}

	extra(): NavigationChild<EC, ET> | null {
		for (const child of this.children.children()) {
			if (child.instance.extra !== null) { return child.instance.extra; }
		}
		return null;
	}

	mode(): ChildPanelsMode {
		return this.children.state()[0].configuration.panels.mode;
	}

	panels(): Panels<MC, DC, EC> {
		const panels = untrack((): Panels<MC, DC, EC> => {
			return this.children.state()[0].configuration.panels;
		});
		return {
			main: panels.main,
			details: panels.details,
			extra: panels.extra,
			mode: panels.mode,
		};
	}

	navigate(transformer: (panels: Panels<MC, DC, EC>) => Panels<MC, DC, EC>): void {
		this.children.navigate(panelsState<MC, DC, EC>(
			transformer(this.panels()),
			this.mainKey,
			this.detailsKey,
			this.extraKey,
		));
	}

	navigateTo(main: MC, details: DC | null, extra: EC | null): void {
		this.navigate((panels: Panels<MC, DC, EC>): Panels<MC, DC, EC> => {
			return { main, details, extra, mode: panels.mode };
		});
	}

	navigateToDetails(details: DC | null, extra: EC | null): void {
		this.navigate((panels: Panels<MC, DC, EC>): Panels<MC, DC, EC> => {
			return { main: panels.main, details, extra, mode: panels.mode };
		});
	}

	navigateToExtra(extra: EC | null): void {
		this.navigate((panels: Panels<MC, DC, EC>): Panels<MC, DC, EC> => {
			return { main: panels.main, details: panels.details, extra, mode: panels.mode };
		});
	}

	activateMain(main: MC): void {
		this.navigate((panels: Panels<MC, DC, EC>): Panels<MC, DC, EC> => {
			return { main, details: panels.details, extra: panels.extra, mode: panels.mode };
		});
	}

	activateDetails(details: DC): void {
		this.navigateToDetails(details, this.panels().extra);
	}

	dismissDetails(): void {
		this.navigateToDetails(null, this.panels().extra);
	}

	activateExtra(extra: EC): void {
		this.navigateToExtra(extra);
	}

	dismissExtra(): void {
		this.navigateToExtra(null);
	}

	pop(): boolean {
		const panels = this.panels();
		if (panels.extra !== null) {
			this.dismissExtra();
			return true;
		}
		if (panels.details !== null) {
			this.dismissDetails();
			return true;
		}
		return false;
	}

	setMode(mode: ChildPanelsMode): void {
		this.navigate((panels: Panels<MC, DC, EC>): Panels<MC, DC, EC> => {
			return { main: panels.main, details: panels.details, extra: panels.extra, mode };
		});
	}

	back(): boolean {
		if (this.panels().mode !== ChildPanelsMode.Single) { return false; }
		return this.pop();
	}

	dispose(): void {
		this.children.dispose();
	}
}

export function createChildPanels<MC, MT, DC, DT, EC, ET>(
	initial: Panels<MC, DC, EC>,
	mainKey: (configuration: MC) => string,
	detailsKey: (configuration: DC) => string,
	extraKey: (configuration: EC) => string,
	mainFactory: (configuration: Accessor<MC>, active: Accessor<boolean>) => MT,
	detailsFactory: (configuration: Accessor<DC>, active: Accessor<boolean>) => DT,
	extraFactory: (configuration: Accessor<EC>, active: Accessor<boolean>) => ET,
): ChildPanels<MC, MT, DC, DT, EC, ET> {
	const children = createChildren<Panel<MC, DC, EC>, PanelChild<MC, MT, DC, DT, EC, ET>>(
		panelsState<MC, DC, EC>(initial, mainKey, detailsKey, extraKey),
		(
			configuration: Accessor<Panel<MC, DC, EC>>,
			active: Accessor<boolean>,
		): PanelChild<MC, MT, DC, DT, EC, ET> => {
			const panels = configuration().panels;
			return match (configuration().kind) {
				PanelKind.Main => ({
					main: panelChild<MC, MT>(
						mainKey(panels.main),
						createMemo<MC>((): MC => configuration().panels.main),
						active,
						mainFactory,
					),
					details: null,
					extra: null,
				}),
				PanelKind.Details => ({
					main: null,
					details: panelChild<DC, DT>(
						detailsKey(panels.details as DC),
						createMemo<DC>((): DC => configuration().panels.details as DC),
						active,
						detailsFactory,
					),
					extra: null,
				}),
				PanelKind.Extra => ({
					main: null,
					details: null,
					extra: panelChild<EC, ET>(
						extraKey(panels.extra as EC),
						createMemo<EC>((): EC => configuration().panels.extra as EC),
						active,
						extraFactory,
					),
				}),
			};
		},
	);
	return new ChildPanels<MC, MT, DC, DT, EC, ET>(children, mainKey, detailsKey, extraKey);
}
