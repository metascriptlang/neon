import { Accessor, createSignal } from "../../src/core/signal";
import { createResource } from "../../src/core/resource";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { NeonNode } from "../../src/render/node";
import { NeonEvent } from "../../src/render/event";
import { View, Text, Pressable, TextInput, ScrollView } from "../../src/components/primitives";
import { FlatList, ListRenderItemInfo } from "../../src/components/flatList";
import { Image } from "../../src/components/image";
import { Button } from "../../src/components/button";
import { Switch } from "../../src/components/switch";
import { ActivityIndicator } from "../../src/components/activityIndicator";
import { Show } from "../../src/macros/ui/flow";
import { Product, CatalogError, fetchProducts, saveProduct, setOffline, formatPrice } from "./catalogData";

const styles = createStyles({
	screen: { flex: 1, flexDirection: "column", backgroundColor: "#1e1e2e" },
	header: { flexDirection: "row", alignItems: "center", gap: 12, padding: 16, backgroundColor: "#181825" },
	title: { color: "#cdd6f4", fontSize: 22, fontWeight: "bold", flex: 1 },
	search: { margin: 12, paddingLeft: 12, paddingRight: 12, height: 44, borderRadius: 8, backgroundColor: "#313244", color: "#cdd6f4", fontSize: 16 },
	toolbar: { flexDirection: "row", alignItems: "center", gap: 8, paddingLeft: 16, paddingRight: 16, paddingBottom: 8 },
	muted: { color: "#a6adc8", fontSize: 14 },
	list: { flex: 1 },
	row: { flexDirection: "row", alignItems: "flex-start", padding: 12, gap: 12, backgroundColor: "#1e1e2e" },
	separator: { height: 1, backgroundColor: "#313244", marginLeft: 80 },
	thumb: { width: 56, height: 56, borderRadius: 8, backgroundColor: "#45475a" },
	initials: { width: 56, height: 56, borderRadius: 8, backgroundColor: "#45475a", alignItems: "center", justifyContent: "center" },
	initialsText: { color: "#cdd6f4", fontSize: 20, fontWeight: "bold" },
	rowBody: { flex: 1, flexDirection: "column", gap: 4 },
	rowTitle: { color: "#cdd6f4", fontSize: 17, fontWeight: "bold" },
	rowDescription: { color: "#a6adc8", fontSize: 14 },
	price: { color: "#a6e3a1", fontSize: 16, fontWeight: "bold" },
	empty: { alignItems: "center", padding: 32 },
	center: { flex: 1, alignItems: "center", justifyContent: "center", gap: 12, padding: 24 },
	message: { color: "#cdd6f4", fontSize: 16 },
	error: { color: "#f38ba8", fontSize: 16 },
	back: { paddingTop: 6, paddingBottom: 6, paddingRight: 8 },
	backText: { color: "#89b4fa", fontSize: 17 },
	hero: { width: 220, height: 220, borderRadius: 12, backgroundColor: "#45475a" },
	detail: { padding: 16, gap: 12, alignItems: "center" },
	detailTitle: { color: "#cdd6f4", fontSize: 24, fontWeight: "bold" },
	detailText: { color: "#bac2de", fontSize: 16 },
	form: { padding: 16, gap: 8 },
	label: { color: "#a6adc8", fontSize: 14 },
	field: { paddingLeft: 12, paddingRight: 12, height: 44, borderRadius: 8, backgroundColor: "#313244", color: "#cdd6f4", fontSize: 16 },
	actions: { flexDirection: "row", gap: 12, paddingTop: 12, alignItems: "center" },
});

function initialsOf(title: string): string {
	const words = title.split(" ");
	let out = "";
	for (const w of words) {
		if (w.length > 0 && out.length < 2) { out += w.charAt(0).toUpperCase(); }
	}
	return out;
}

function Thumb(props: { uri: Accessor<string>; title: Accessor<string>; large: Accessor<boolean> }): NeonNode {
	const [failed, setFailed] = createSignal(false);
	return <Show when={!failed()} fallback={<View style={styles.initials} accessibilityLabel={props.title()} accessibilityRole="image"><Text style={styles.initialsText}>{initialsOf(props.title())}</Text></View>}>
		<Image source={{ uri: props.uri() }} style={props.large() ? styles.hero : styles.thumb} resizeMode="cover"
			accessibilityLabel={props.title()} onError={(e: NeonEvent): void => { setFailed(true); }} />
	</Show>;
}

function errorText(e: CatalogError): string {
	return match (e) {
		CatalogError.Offline => "Could not reach the catalog. Check the connection and try again.",
	};
}

function ProductList(props: {
	query: Accessor<string>;
	setQuery: (q: string) => void;
	items: Accessor<Product[] | null>;
	loading: Accessor<boolean>;
	error: Accessor<CatalogError | null>;
	offline: Accessor<boolean>;
	setOffline: (v: boolean) => void;
	retry: () => void;
	open: (p: Product) => void;
}): NeonNode {
	const rows = (): Product[] => {
		const v = props.items();
		return v === null ? [] : v as Product[];
	};
	return <View style={styles.screen}>
		<View style={styles.header}>
			<Text style={styles.title} accessibilityRole="header">Catalog</Text>
			<Show when={props.loading()}><ActivityIndicator color="#89b4fa" accessibilityLabel="Loading products" /></Show>
		</View>
		<TextInput style={styles.search} value={props.query()} placeholder="Search products" placeholderTextColor="#7f849c"
			returnKeyType="search" autoCapitalize="none" accessibilityLabel="Search products"
			onChangeText={(t: string): void => { props.setQuery(t); }} />
		<View style={styles.toolbar}>
			<Text style={styles.muted}>{props.items() === null ? "" : rows().length.toString() + (rows().length === 1 ? " product" : " products")}</Text>
			<View style={{ flex: 1 }} />
			<Text style={styles.muted}>Offline</Text>
			<Switch value={props.offline()} onValueChange={(v: boolean): void => { props.setOffline(v); }} accessibilityLabel="Simulate offline" />
		</View>
		<Show when={props.error() === null} fallback={<View style={styles.center}>
			<Text style={styles.error}>{props.error() === null ? "" : errorText(props.error() as CatalogError)}</Text>
			<Button title="Retry" onPress={(e: NeonEvent): void => { props.retry(); }} />
		</View>}>
			<Show when={props.items() !== null} fallback={<View style={styles.center}><ActivityIndicator size="large" color="#89b4fa" /><Text style={styles.message}>Loading products</Text></View>}>
				<FlatList data={rows()} style={styles.list} keyboardShouldPersistTaps="handled" keyboardDismissMode="on-drag"
					refreshing={props.loading()} onRefresh={(): void => { props.retry(); }}
					ItemSeparatorComponent={<View style={styles.separator} />}
					ListEmptyComponent={<View style={styles.empty}><Text style={styles.message}>{`No products match "${props.query()}"`}</Text></View>}
					renderItem={(info: ListRenderItemInfo<Product>): NeonNode =>
						<Pressable style={styles.row} accessibilityRole="button" accessibilityLabel={info.item.title + ", " + formatPrice(info.item.price)}
							onPress={(e: NeonEvent): void => { props.open(info.item); }}>
							<Thumb uri={info.item.image} title={info.item.title} large={false} />
							<View style={styles.rowBody}>
								<Text style={styles.rowTitle}>{info.item.title}</Text>
								<Text style={styles.rowDescription}>{info.item.description}</Text>
							</View>
							<Text style={styles.price}>{formatPrice(info.item.price)}</Text>
						</Pressable>} />
			</Show>
		</Show>
	</View>;
}

function ProductDetail(props: { product: Accessor<Product>; back: () => void; edit: () => void }): NeonNode {
	return <View style={styles.screen}>
		<View style={styles.header}>
			<Pressable style={styles.back} accessibilityRole="button" accessibilityLabel="Back to catalog" onPress={(e: NeonEvent): void => { props.back(); }}>
				<Text style={styles.backText}>‹ Catalog</Text>
			</Pressable>
		</View>
		<ScrollView>
			<View style={styles.detail}>
				<Thumb uri={props.product().image} title={props.product().title} large={true} />
				<Text style={styles.detailTitle} accessibilityRole="header">{props.product().title}</Text>
				<Text style={styles.price}>{formatPrice(props.product().price)}</Text>
				<Text style={styles.detailText}>{props.product().description}</Text>
				<Button title="Edit" onPress={(e: NeonEvent): void => { props.edit(); }} accessibilityHint="Opens the edit form" />
			</View>
		</ScrollView>
	</View>;
}

async function submitEdit(id: string, title: string, description: string, price: string,
	setSaving: (v: boolean) => void, setProblem: (v: string) => void, saved: (p: Product) => void): Promise<void> {
	setSaving(true);
	setProblem("");
	const result = await saveProduct(id, title, description, price);
	setSaving(false);
	if (result.ok) {
		saved(result.value);
	} else {
		setProblem(result.error);
	}
}

function ProductEdit(props: { product: Accessor<Product>; cancel: () => void; saved: (p: Product) => void }): NeonNode {
	const start = props.product();
	const [title, setTitle] = createSignal(start.title);
	const [price, setPrice] = createSignal(Math.round(start.price).toString());
	const [description, setDescription] = createSignal(start.description);
	const [saving, setSaving] = createSignal(false);
	const [problem, setProblem] = createSignal("");
	const submit = (): void => {
		submitEdit(start.id, title(), description(), price(), (v: boolean): void => { setSaving(v); }, (v: string): void => { setProblem(v); }, props.saved);
	};
	return <View style={styles.screen}>
		<View style={styles.header}>
			<Pressable style={styles.back} accessibilityRole="button" accessibilityLabel="Cancel editing" onPress={(e: NeonEvent): void => { props.cancel(); }}>
				<Text style={styles.backText}>‹ Cancel</Text>
			</Pressable>
			<Text style={styles.title} accessibilityRole="header">Edit product</Text>
		</View>
		<ScrollView keyboardShouldPersistTaps="handled">
			<View style={styles.form}>
				<Text style={styles.label}>Title</Text>
				<TextInput style={styles.field} value={title()} onChangeText={(t: string): void => { setTitle(t); }} accessibilityLabel="Title" returnKeyType="next" />
				<Text style={styles.label}>Price</Text>
				<TextInput style={styles.field} value={price()} keyboardType="decimal-pad" onChangeText={(t: string): void => { setPrice(t); }} accessibilityLabel="Price" />
				<Text style={styles.label}>Description</Text>
				<TextInput style={styles.field} value={description()} onChangeText={(t: string): void => { setDescription(t); }} accessibilityLabel="Description"
					returnKeyType="done" onSubmitEditing={(e: NeonEvent): void => { submit(); }} />
				<Show when={problem() !== ""}><Text style={styles.error} accessibilityRole="alert">{problem()}</Text></Show>
				<View style={styles.actions}>
					<Button title={saving() ? "Saving" : "Save"} disabled={saving()} onPress={(e: NeonEvent): void => { submit(); }} />
					<Show when={saving()}><ActivityIndicator color="#89b4fa" accessibilityLabel="Saving" /></Show>
				</View>
			</View>
		</ScrollView>
	</View>;
}

export function CatalogApp(): NeonNode {
	const [screen, setScreen] = createSignal<int32>(0);
	const [query, setQuery] = createSignal("");
	const [offline, setOfflineSignal] = createSignal(false);
	const [current, setCurrent] = createSignal<Product | null>(null);
	const [items, actions] = createResource(query, fetchProducts);
	const product = (): Product => current() as Product;
	return <View style={{ flex: 1 }}>
		<Show when={screen() === 0}>
			<ProductList query={query()} setQuery={(q: string): void => { setQuery(q); }}
				items={items()} loading={actions.loading()} error={actions.error()}
				offline={offline()} setOffline={(v: boolean): void => { setOfflineSignal(v); setOffline(v); actions.refetch(); }}
				retry={(): void => { actions.refetch(); }}
				open={(p: Product): void => { setCurrent(p); setScreen(1); }} />
		</Show>
		<Show when={screen() === 1 && current() !== null}>
			<ProductDetail product={product()} back={(): void => { setScreen(0); }} edit={(): void => { setScreen(2); }} />
		</Show>
		<Show when={screen() === 2 && current() !== null}>
			<ProductEdit product={product()} cancel={(): void => { setScreen(1); }}
				saved={(p: Product): void => { setCurrent(p); actions.refetch(); setScreen(1); }} />
		</Show>
	</View>;
}
