import { Accessor, accessor } from "../core/signal";
import { createMemo } from "../core/memo";
import { NeonNode, Host } from "../render/hostTypes";
import { regionNode } from "../render/node";
import { Row, makeRow } from "../render/reconcile";
import { Style, TextAlign } from "../render/style";
import { Platform } from "../api/platform";
import { NeonEvent } from "../render/event";
import { createComponent } from "../render/component";
import { View, Text, Pressable } from "../components/primitives";
import { Show } from "../macros/ui/flow";
import {
	DrawerAction,
	NavigatorCore,
	Navigation,
	NavigatorKind,
	NavigatorLink,
	ScopeContext,
	ScreenOptions,
	ScreenProps,
	currentScope,
	screenScope,
} from "./core";

type RowList = () => Row[];

export const HEADER_TINT = "#007aff";
export const HEADER_BACKGROUND = "#ffffff";
export const HEADER_BORDER = "#d8d8d8";
export const TITLE_COLOR = "#1c1c1e";

export function Slot(props: { node: Accessor<NeonNode | null> }): NeonNode {
	const read = props.node;
	return regionNode((h: Host): RowList => createMemo<Row[]>((): Row[] => {
		const node = read();
		if (node === null) { return [] as Row[]; }
		return [makeRow(node as NeonNode)];
	}));
}

function tintOf(tint: Accessor<string> | null): Accessor<string> {
	return accessor((): string => tint === null ? HEADER_TINT : (tint as Accessor<string>)());
}

const BACK_BUTTON: Style = {
	flexDirection: "row",
	alignItems: "center",
	paddingLeft: 8,
	paddingRight: 8,
	height: 44,
};

const MENU_BUTTON: Style = {
	paddingLeft: 12,
	paddingRight: 12,
	height: 44,
	justifyContent: "center",
};

export function HeaderBackButton(props: {
	label?: Accessor<string> | null;
	tintColor?: Accessor<string> | null;
	onPress: () => void;
}): NeonNode {
	const label = props.label;
	const tint = props.tintColor;
	const color = tintOf(tint);
	const text = accessor((): string => label === null ? "Back" : (label as Accessor<string>)());
	const press = props.onPress;
	return <Pressable style={BACK_BUTTON}
		accessibilityRole="button" accessibilityLabel="Back"
		onPress={(e: NeonEvent): void => { press(); }}>
		<Text style={{ color: color(), fontSize: 17 }}>{"‹ " + text()}</Text>
	</Pressable>;
}

export function DrawerToggleButton(props: { tintColor?: Accessor<string> | null }): NeonNode {
	const tint = props.tintColor;
	const color = tintOf(tint);
	const scope = currentScope("DrawerToggleButton");
	const toggle = (e: NeonEvent): void => {
		let link: NavigatorLink | null = scope.link;
		while (link !== null) {
			const here = link as NavigatorLink;
			if (here.drawerAction(DrawerAction.Toggle)) { return; }
			link = here.parent();
		}
		throw new Error("DrawerToggleButton: no drawer navigator around this screen");
	};
	return <Pressable style={MENU_BUTTON}
		accessibilityRole="button" accessibilityLabel="Show navigation menu" onPress={toggle}>
		<Text style={{ color: color(), fontSize: 22 }}>☰</Text>
	</Pressable>;
}

export function Header(props: {
	title: Accessor<string>;
	options: Accessor<ScreenOptions>;
	back: Accessor<boolean>;
	backTitle: Accessor<string>;
	onBack: () => void;
	menu: Accessor<boolean>;
}): NeonNode {
	const options = props.options;
	const tint = accessor((): string => {
		const color = options().headerTintColor;
		return color === null ? HEADER_TINT : color as string;
	});
	const bar = accessor((): Style => {
		const base: Style = {
			flexDirection: "row",
			alignItems: "center",
			height: 52,
			paddingLeft: 4,
			paddingRight: 8,
			backgroundColor: HEADER_BACKGROUND,
		};
		const extra = options().headerStyle;
		if (extra === null) { return base; }
		return { ...base, backgroundColor: (extra as Style).backgroundColor };
	});
	const left = accessor((): NeonNode | null => options().headerLeft);
	const right = accessor((): NeonNode | null => options().headerRight);
	const hasLeft = accessor((): boolean => options().headerLeft !== null);
	const showBack = accessor((): boolean => !hasLeft() && props.back());
	const showMenu = accessor((): boolean => !hasLeft() && !props.back() && props.menu());
	const align = accessor((): TextAlign => {
		const own = options().headerTitleAlign;
		if (own !== null) { return own === "center" ? "center" : "left"; }
		return Platform.OS === "ios" ? "center" : "left";
	});
	const titleBox = accessor((): Style => ({
		flex: 1,
		flexDirection: "row",
		justifyContent: align() === "center" ? "center" : "flex-start",
		paddingLeft: 8,
		paddingRight: 8,
	}));
	const titleColor = accessor((): string => {
		const color = options().headerTintColor;
		return color === null ? TITLE_COLOR : color as string;
	});
	const titleText = accessor((): Style => ({
		color: titleColor(),
		fontSize: 17,
		fontWeight: "bold",
		textAlign: align(),
	}));
	const onBack = props.onBack;
	return <View style={{ flexDirection: "column" }}><View style={bar}>
		<Show when={showBack()}>
			<HeaderBackButton label={props.backTitle} tintColor={tint} onPress={onBack} />
		</Show>
		<Show when={showMenu()}>
			<DrawerToggleButton tintColor={tint} />
		</Show>
		<Slot node={left} />
		<View style={titleBox}>
			<Text style={titleText}
				accessibilityRole="header">{props.title()}</Text>
		</View>
		<Slot node={right} />
	</View><View style={{ height: 1, backgroundColor: HEADER_BORDER }} /></View>;
}

export function titleOf<P>(entry: Navigation<P>): string {
	const options = entry.options();
	const headerTitle = options.headerTitle;
	if (headerTitle !== null) { return headerTitle as string; }
	const title = options.title;
	return title === null ? entry.route.name : title as string;
}

export function shown(value: boolean | null, fallback: boolean): boolean {
	return value === null ? fallback : value as boolean;
}

export function screenView<P>(core: NavigatorCore<P>, entry: Navigation<P>): NeonNode {
	const scope = screenScope<P>(core, entry);
	const key = entry.route.key;
	const options = accessor((): ScreenOptions => entry.options());
	const position = accessor((): int32 => {
		const list = core.entries();
		for (let i = 0; i < list.length; i += 1) {
			if (list[i].route.key === key) { return i as int32; }
		}
		return -1;
	});
	const visible = accessor((): boolean => {
		if (!core.isStack()) { return core.currentKey() === key; }
		const at = position();
		return at >= 0 && at >= core.visibleFrom();
	});
	const frame = accessor((): Style => ({
		position: "absolute",
		top: 0,
		left: 0,
		right: 0,
		bottom: 0,
		flexDirection: "column",
		display: visible() ? "flex" : "none",
	}));
	const headerShown = accessor((): boolean => {
		const presentation = options().presentation;
		const overlay = presentation !== null && presentation === "transparentModal";
		return shown(options().headerShown, !overlay);
	});
	const back = accessor((): boolean => core.kind === NavigatorKind.Stack && position() > 0);
	const backTitle = accessor((): string => {
		const at = position();
		if (at <= 0) { return "Back"; }
		const own = options().headerBackTitle;
		if (own !== null) { return own as string; }
		return titleOf<P>(core.entries()[at - 1]);
	});
	const menu = accessor((): boolean => core.kind === NavigatorKind.Drawer);
	const title = accessor((): string => titleOf<P>(entry));
	const props: ScreenProps<P> = { navigation: entry, route: entry.route };
	const body = createComponent(entry.config.component, props);
	const goBack = (): void => { entry.goBack(); };
	return <ScopeContext.Provider value={scope as unknown}>
		<View style={frame}>
			<Show when={headerShown()}>
				<Header title={title} options={options} back={back} backTitle={backTitle}
					onBack={goBack} menu={menu} />
			</Show>
			<View style={{ flex: 1, flexDirection: "column" }}>{body}</View>
		</View>
	</ScopeContext.Provider>;
}
