import { Accessor, createSignal } from "../../src/core/signal";
import { createMemo } from "../../src/core/memo";
import { NeonNode } from "../../src/render/node";
import { NeonEvent } from "../../src/render/event";
import { Style } from "../../src/render/style";
import { View, Text, TextInput, TextInputHandle, ScrollView } from "../../src/components/primitives";
import { Switch } from "../../src/components/switch";
import { Button } from "../../src/components/button";
import { Show } from "../../src/macros/ui/flow";
import { useColorScheme, useKeyboard, useWindowDimensions } from "../../src/render/environment";

interface Theme {
	background: string;
	surface: string;
	text: string;
	muted: string;
	accent: string;
	field: string;
}

const LIGHT: Theme = { background: "#eff1f5", surface: "#ffffff", text: "#4c4f69", muted: "#6c6f85", accent: "#1e66f5", field: "#e6e9ef" };
const DARK: Theme = { background: "#1e1e2e", surface: "#313244", text: "#cdd6f4", muted: "#a6adc8", accent: "#89b4fa", field: "#45475a" };
const WIDE_LAYOUT = 600;

function Section(props: { title: Accessor<string>; theme: Accessor<Theme>; style: Accessor<Style>; children: NeonNode }): NeonNode {
	return <View style={{ ...props.style(), backgroundColor: props.theme().surface, borderRadius: 12, padding: 16, gap: 12 }}>
		<Text style={{ color: props.theme().accent, fontSize: 14, fontWeight: "bold" }} accessibilityRole="header">{props.title().toUpperCase()}</Text>
		{props.children}
	</View>;
}

function ToggleRow(props: { label: Accessor<string>; detail: Accessor<string>; value: Accessor<boolean>; onChange: (v: boolean) => void; theme: Accessor<Theme>; large: Accessor<boolean> }): NeonNode {
	return <View style={{ flexDirection: "row", alignItems: "center", gap: 12 }}>
		<View style={{ flex: 1, gap: 2 }}>
			<Text style={{ color: props.theme().text, fontSize: props.large() ? 20 : 17 }}>{props.label()}</Text>
			<Text style={{ color: props.theme().muted, fontSize: props.large() ? 16 : 13 }}>{props.detail()}</Text>
		</View>
		<Switch value={props.value()} onValueChange={(v: boolean): void => { props.onChange(v); }}
			accessibilityLabel={props.label()} accessibilityHint={props.detail()}
			trackColorOn={props.theme().accent} />
	</View>;
}

export function SettingsApp(): NeonNode {
	const system = useColorScheme();
	const window = useWindowDimensions();
	const keyboard = useKeyboard();
	const [followSystem, setFollowSystem] = createSignal(true);
	const [darkChoice, setDarkChoice] = createSignal(false);
	const [notifications, setNotifications] = createSignal(true);
	const [largeText, setLargeText] = createSignal(false);
	const [name, setName] = createSignal("Ada Lovelace");
	const [email, setEmail] = createSignal("ada@example.com");
	const [focused, setFocused] = createSignal("none");
	const [saved, setSaved] = createSignal("");
	const fields: TextInputHandle[] = [];

	const dark = createMemo((): boolean => followSystem() ? system() === "dark" : darkChoice());
	const theme = createMemo((): Theme => dark() ? DARK : LIGHT);
	const wide = createMemo((): boolean => window().width >= WIDE_LAYOUT);
	const column = (): Style => wide() ? { flex: 1, flexBasis: 0 } : { alignSelf: "stretch" };
	const fieldStyle = (): Style => ({
		height: largeText() ? 52 : 44, paddingLeft: 12, paddingRight: 12, borderRadius: 8,
		backgroundColor: theme().field, color: theme().text, fontSize: largeText() ? 20 : 16,
	});
	const label = (): Style => ({ color: theme().muted, fontSize: largeText() ? 16 : 13 });
	const save = (): void => {
		setSaved(`Saved ${name()} <${email()}>`);
		for (const f of fields) { f.blur(); }
	};

	return <View style={{ flex: 1, backgroundColor: theme().background }}>
		<View style={{ padding: 16, paddingBottom: 8, gap: 4 }}>
			<Text style={{ color: theme().text, fontSize: largeText() ? 30 : 26, fontWeight: "bold" }} accessibilityRole="header">Settings</Text>
			<Text style={{ color: theme().muted, fontSize: 13 }}>{`${wide() ? "Wide" : "Compact"} layout · ${Math.round(window().width)}×${Math.round(window().height)} · ${dark() ? "dark" : "light"} theme (system ${system()})`}</Text>
			<Text style={{ color: theme().muted, fontSize: 13 }}>{`Focus: ${focused()} · keyboard ${keyboard().visible ? Math.round(keyboard().height).toString() + "pt" : "hidden"}`}</Text>
		</View>
		<ScrollView keyboardShouldPersistTaps="handled" keyboardDismissMode="on-drag">
			<View style={{ flexDirection: wide() ? "row" : "column", alignItems: "flex-start", gap: 16, padding: 16 }}>
				<Section title="Profile" theme={theme()} style={column()}>
					<Text style={label()}>Name</Text>
					<TextInput style={fieldStyle()} value={name()} placeholder="Your name" accessibilityLabel="Name" autoCapitalize="words"
						returnKeyType="next" blurOnSubmit={false}
						ref={(h: TextInputHandle): void => { fields.push(h); }}
						onFocus={(e: NeonEvent): void => { setFocused("name"); }}
						onBlur={(e: NeonEvent): void => { if (focused() === "name") { setFocused("none"); } }}
						onChangeText={(t: string): void => { setName(t); }}
						onSubmitEditing={(e: NeonEvent): void => { fields[1].focus(); }} />
					<Text style={label()}>Email</Text>
					<TextInput style={fieldStyle()} value={email()} placeholder="you@example.com" accessibilityLabel="Email"
						keyboardType="email-address" autoCapitalize="none" autoCorrect={false} returnKeyType="done"
						ref={(h: TextInputHandle): void => { fields.push(h); }}
						onFocus={(e: NeonEvent): void => { setFocused("email"); }}
						onBlur={(e: NeonEvent): void => { if (focused() === "email") { setFocused("none"); } }}
						onChangeText={(t: string): void => { setEmail(t); }}
						onSubmitEditing={(e: NeonEvent): void => { save(); }} />
					<Button title="Save profile" color={theme().accent} onPress={(e: NeonEvent): void => { save(); }} accessibilityHint="Saves your name and email" />
					<Show when={saved() !== ""}><Text style={{ color: theme().text, fontSize: 15 }} accessibilityRole="alert">{saved()}</Text></Show>
				</Section>
				<Section title="Appearance" theme={theme()} style={column()}>
					<ToggleRow label="Use system theme" detail={`Follows the device setting (${system()})`} value={followSystem()}
						onChange={(v: boolean): void => { setFollowSystem(v); }} theme={theme()} large={largeText()} />
					<Show when={!followSystem()}>
						<ToggleRow label="Dark mode" detail="Dark colours for this app" value={darkChoice()}
							onChange={(v: boolean): void => { setDarkChoice(v); }} theme={theme()} large={largeText()} />
					</Show>
					<ToggleRow label="Large text" detail="Bigger type for every label" value={largeText()}
						onChange={(v: boolean): void => { setLargeText(v); }} theme={theme()} large={largeText()} />
					<ToggleRow label="Notifications" detail={notifications() ? "You will be notified" : "Muted"} value={notifications()}
						onChange={(v: boolean): void => { setNotifications(v); }} theme={theme()} large={largeText()} />
				</Section>
			</View>
			<View style={{ height: keyboard().height }} />
		</ScrollView>
	</View>;
}
