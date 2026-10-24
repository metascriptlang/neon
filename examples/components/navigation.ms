import { Accessor, createSignal, untrack } from "../../src/core/signal";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { For } from "../../src/macros/ui/flow";
import { NeonNode } from "../../src/render/node";
import { NeonEvent } from "../../src/render/event";
import { View, Text, Pressable, TextInput, ScrollView } from "../../src/components/primitives";
import {
	DrawerToggleButton,
	LinkingOptions,
	NavigationContainer,
	NavigationContainerRef,
	ScreenProps,
	TabBarIconProps,
	createBottomTabNavigator,
	createDrawerNavigator,
	createNavigationContainerRef,
	createStackNavigator,
	DarkTheme,
	DefaultTheme,
	useIsFocused,
	useTheme,
	useNavigation,
	useRoute,
} from "../../src/navigation/index";

export interface ItemParams {
	id: int32;
}

interface Item {
	id: int32;
	name: Accessor<string>;
	rename: (name: string) => void;
}

function makeItem(id: int32, name: string): Item {
	const [read, write] = createSignal<string>(name);
	return { id, name: read, rename: (next: string): void => { write(next); } };
}

const items: Item[] = [
	makeItem(1, "Neon lamp"),
	makeItem(2, "Void shader"),
	makeItem(3, "Yoga mat"),
	makeItem(4, "Ion window"),
	makeItem(5, "Lightcube"),
];

function itemOf(id: int32): Item {
	for (const item of items) {
		if (item.id === id) { return item; }
	}
	throw new Error("no item " + id.toString());
}

const styles = createStyles({
	screen: { flex: 1, flexDirection: "column", gap: 12, padding: 16, backgroundColor: "#f2f2f7" },
	title: { color: "#1c1c1e", fontSize: 22, fontWeight: "bold" },
	body: { color: "#3a3a3c", fontSize: 16 },
	row: { flexDirection: "row", alignItems: "center", padding: 14, backgroundColor: "#ffffff", borderRadius: 10 },
	rowText: { color: "#1c1c1e", fontSize: 17, flex: 1 },
	chevron: { color: "#c7c7cc", fontSize: 20 },
	button: { paddingTop: 12, paddingBottom: 12, paddingLeft: 16, paddingRight: 16, backgroundColor: "#007aff", borderRadius: 10, alignItems: "center" },
	buttonText: { color: "#ffffff", fontSize: 17, fontWeight: "bold" },
	input: { height: 44, paddingLeft: 12, paddingRight: 12, backgroundColor: "#ffffff", borderRadius: 10, color: "#1c1c1e", fontSize: 17 },
	headerButton: { paddingLeft: 12, paddingRight: 12, height: 44, justifyContent: "center" },
	headerButtonText: { color: "#007aff", fontSize: 17 },
});

function Counter(props: { name: string; label: Accessor<string> }): NeonNode {
	const [count, setCount] = createSignal<int32>(0);
	const name = props.name;
	return <View style={{ flexDirection: "row", alignItems: "center", gap: 12 }}>
		<Text style={styles.body}>{props.label() + " " + count().toString()}</Text>
		<Pressable style={styles.button} accessibilityRole="button" accessibilityLabel={"Increment " + name}
			onPress={(e: NeonEvent): void => { setCount(count() + 1); }}>
			<Text style={styles.buttonText}>+1</Text>
		</Pressable>
	</View>;
}

interface HomeParams {
	List: null;
	Detail: ItemParams;
	Edit: ItemParams;
	Settings: null;
}

interface TabParams {
	Home: null;
	Search: null;
	Profile: null;
}

interface DrawerParams {
	Main: null;
	Settings: null;
	About: null;
}

const HomeStack = createStackNavigator<HomeParams>();
const Tab = createBottomTabNavigator<TabParams>();
const Drawer = createDrawerNavigator<DrawerParams>();

function ItemList(props: ScreenProps<HomeParams>): NeonNode {
	const navigation = props.navigation;
	const row = (item: Item, at: Accessor<number>): NeonNode => <Pressable style={styles.row} accessibilityRole="button"
		accessibilityLabel={"Open " + item.name()} onPress={(e: NeonEvent): void => { navigation.navigate("Detail", { id: item.id }); }}>
		<Text style={styles.rowText}>{item.name()}</Text>
		<Text style={styles.chevron}>›</Text>
	</Pressable>;
	return <ScrollView style={{ flex: 1, backgroundColor: "#f2f2f7" }}>
		<View style={styles.screen}>
			<Counter name="home" label="Home taps" />
			<For each={items}>{row}</For>
		</View>
	</ScrollView>;
}

function ItemDetail(props: ScreenProps<HomeParams>): NeonNode {
	const navigation = props.navigation;
	const route = useRoute<HomeParams, "Detail">();
	const item = (): Item => {
		const params = route.params();
		return itemOf(params === null ? 1 : (params as ItemParams).id);
	};
	return <View style={styles.screen}>
		<Text style={styles.title} accessibilityRole="header">{item().name()}</Text>
		<Text style={styles.body}>{"Item number " + item().id.toString()}</Text>
		<Pressable style={styles.button} accessibilityRole="button" accessibilityLabel="Edit item"
			onPress={(e: NeonEvent): void => { navigation.push("Edit", { id: item().id }); }}>
			<Text style={styles.buttonText}>Edit</Text>
		</Pressable>
		<Pressable style={styles.button} accessibilityRole="button" accessibilityLabel="Go to settings"
			onPress={(e: NeonEvent): void => { navigation.navigate("Settings"); }}>
			<Text style={styles.buttonText}>Settings</Text>
		</Pressable>
	</View>;
}

function ItemEdit(props: ScreenProps<HomeParams>): NeonNode {
	const navigation = props.navigation;
	const route = useRoute<HomeParams, "Edit">();
	const params = untrack((): ItemParams | null => route.params());
	const item = itemOf(params === null ? 1 : (params as ItemParams).id);
	const [draft, setDraft] = createSignal<string>(untrack((): string => item.name()));
	const save = (): void => {
		item.rename(draft());
		navigation.goBack();
	};
	navigation.setOptions({
		headerRight: <Pressable style={styles.headerButton} accessibilityRole="button" accessibilityLabel="Save"
			onPress={(e: NeonEvent): void => { save(); }}>
			<Text style={styles.headerButtonText}>Save</Text>
		</Pressable>,
	});
	return <View style={styles.screen}>
		<Text style={styles.body}>Name</Text>
		<TextInput style={styles.input} value={draft()} accessibilityLabel="Item name"
			onChangeText={(text: string): void => { setDraft(text); }} />
	</View>;
}

function HomeTab(props: ScreenProps<TabParams>): NeonNode {
	return <HomeStack.Navigator>
		<HomeStack.Screen name="List" component={ItemList} options={{ title: "Items", headerLeft: <DrawerToggleButton /> }} />
		<HomeStack.Screen name="Detail" component={ItemDetail} options={{ title: "Item" }}
			params={HomeStack.params.of("Detail", {
				parse: (values: Map<string, string>): ItemParams => ({ id: parseInt(values.get("id") ?? "1") as int32 }),
			})} />
		<HomeStack.Screen name="Edit" component={ItemEdit} options={{ title: "Edit item" }} />
	</HomeStack.Navigator>;
}

function SearchTab(props: ScreenProps<TabParams>): NeonNode {
	const navigation = useNavigation<TabParams>();
	const focused = useIsFocused();
	const [unread, setUnread] = createSignal<int32>(0);
	const notify = (e: NeonEvent): void => {
		const count = unread() + 1;
		setUnread(count);
		navigation.setOptions({ tabBarBadge: count.toString() });
	};
	return <View style={styles.screen}>
		<Text style={styles.title}>Search</Text>
		<Counter name="search" label="Searches" />
		<Text style={styles.body}>{focused() ? "Search is focused" : "Search is in the background"}</Text>
		<Pressable style={styles.button} accessibilityRole="button" accessibilityLabel="Add badge" onPress={notify}>
			<Text style={styles.buttonText}>Badge +1</Text>
		</Pressable>
	</View>;
}

function ProfileTab(props: ScreenProps<TabParams>): NeonNode {
	return <View style={styles.screen}>
		<Text style={styles.title}>Profile</Text>
		<Counter name="profile" label="Profile taps" />
	</View>;
}

function glyph(text: string, icon: TabBarIconProps): NeonNode {
	return <Text style={{ color: icon.color, fontSize: icon.focused ? 22 : 20 }}>{text}</Text>;
}

function MainTabs(props: ScreenProps<DrawerParams>): NeonNode {
	return <Tab.Navigator>
		<Tab.Screen name="Home" component={HomeTab} options={{ headerShown: false, tabBarIcon: (icon: TabBarIconProps): NeonNode => glyph("⌂", icon) }} />
		<Tab.Screen name="Search" component={SearchTab} options={{ tabBarIcon: (icon: TabBarIconProps): NeonNode => glyph("⚲", icon) }} />
		<Tab.Screen name="Profile" component={ProfileTab} options={{ tabBarIcon: (icon: TabBarIconProps): NeonNode => glyph("☺", icon) }} />
	</Tab.Navigator>;
}

const [darkTheme, setDarkTheme] = createSignal(false);

function SettingsScreen(props: ScreenProps<DrawerParams>): NeonNode {
	const navigation = props.navigation;
	const theme = useTheme();
	return <View style={{ flex: 1, flexDirection: "column", gap: 12, padding: 16, backgroundColor: theme().colors.background }}>
		<Counter name="settings" label="Settings taps" />
		<Text style={{ color: theme().colors.text, fontSize: 16 }}>{theme().dark ? "Theme: dark" : "Theme: light"}</Text>
		<Pressable style={styles.button} accessibilityRole="button" accessibilityLabel="Toggle dark theme"
			onPress={(e: NeonEvent): void => { setDarkTheme(!darkTheme()); }}>
			<Text style={styles.buttonText}>Toggle theme</Text>
		</Pressable>
		<Pressable style={styles.button} accessibilityRole="button" accessibilityLabel="Back to items"
			onPress={(e: NeonEvent): void => { navigation.navigate("Main"); }}>
			<Text style={styles.buttonText}>Back to items</Text>
		</Pressable>
	</View>;
}

function AboutScreen(props: ScreenProps<DrawerParams>): NeonNode {
	return <View style={styles.screen}>
		<Text style={styles.title}>Neon navigation</Text>
		<Text style={styles.body}>Stack, tabs and drawer in React Navigation's shape.</Text>
	</View>;
}

export const navigationLinking: LinkingOptions = {
	prefixes: ["neonnav://", "https://neon.invalid/nav"],
	config: {
		screens: [
			{
				name: "Main",
				screens: [
					{
						name: "Home",
						screens: [
							{ name: "List", path: "items" },
							{ name: "Detail", path: "items/:id" },
						],
					},
					{ name: "Search", path: "search" },
					{ name: "Profile", path: "profile" },
				],
			},
			{ name: "Settings", path: "settings" },
			{ name: "About", path: "about" },
		],
	},
};

export const navigationRef: NavigationContainerRef = createNavigationContainerRef();

export function NavigationDemo(): NeonNode {
	return <NavigationContainer ref={navigationRef} linking={navigationLinking}
		theme={darkTheme() ? DarkTheme : DefaultTheme}>
		<Drawer.Navigator>
			<Drawer.Screen name="Main" component={MainTabs} options={{ headerShown: false, drawerLabel: "Items" }} />
			<Drawer.Screen name="Settings" component={SettingsScreen} />
			<Drawer.Screen name="About" component={AboutScreen} />
		</Drawer.Navigator>
	</NavigationContainer>;
}
