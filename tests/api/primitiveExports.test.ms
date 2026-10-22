import { flush } from "../../src/core/runtime";
import {
	ActivityIndicator,
	Host,
	HostNode,
	Image,
	ImageLoader,
	ImageProps,
	ImageResizeMode,
	ImageSource,
	IndicatorSize,
	KeyboardAvoidingBehavior,
	KeyboardAvoidingView,
	Modal,
	ModalAnimationType,
	NeonNode,
	Portal,
	RefreshControl,
	SafeAreaView,
	ScrollView,
	Style,
	Switch,
	Text,
	TextInput,
	TextInputHandle,
	TouchableHighlight,
	TouchableOpacity,
	TouchableWithoutFeedback,
	View,
	accessor,
	createContext,
	createRoot,
	createSignal,
	element,
	installAppServices,
	render,
	useContext,
} from "../../src/index";
import {
	MockNode,
	fireEvent,
	fireEventWith,
	fireTouch,
	mockHost,
	mockNode,
	mockToString,
} from "../../src/render/host";
import { neonEvent } from "../../src/render/event";
import { publishKeyboard, publishSafeArea } from "../../src/render/environment";
import { FakeServices } from "./fakeServices";

function attrOf(node: MockNode, name: string): string {
	for (const attr of node.attrs) {
		if (attr.name === name) { return attr.value ?? ""; }
	}
	return "<unset>";
}

function overlayOf(host: Host, root: MockNode): MockNode {
	return (host.overlayRoot as (node: HostNode) => HostNode)(root as unknown as HostNode)
		as unknown as MockNode;
}

test "public primitive exports mount a typed Image and expose its service loader" {
	const [uri, setUri] = createSignal("data:first");
	const mode: ImageResizeMode = "contain";
	const props: ImageProps = {
		source: accessor((): ImageSource => ({ uri: uri() })),
		resizeMode: accessor((): ImageResizeMode => mode),
	};
	const image: NeonNode = Image(props);
	const root = mockNode("root");
	const dispose = render(image, mockHost(), root as unknown as HostNode);
	const mounted = root.children[0];
	assert mounted.tag === "image";
	assert attrOf(mounted, "source") === "data:first";
	assert attrOf(mounted, "resizeMode") === "contain";
	setUri("data:second");
	flush();
	assert attrOf(mounted, "source") === "data:second";
	dispose();
	setUri("data:after-dispose");
	flush();
	assert attrOf(mounted, "source") === "data:second";

	const services = new FakeServices();
	services.install();
	let dimensions = "";
	ImageLoader.getSize("data:size", (width: float64, height: float64): void => {
		dimensions = `${width}x${height}`;
	});
	assert services.joined() === "imageSize data:size";
	services.imageDone[0](12, 24, "");
	assert dimensions === "12x24";
	installAppServices(null);
}

test "public inset and keyboard controls retain typed TextInputHandle lifetime" {
	publishSafeArea(0, 0, 0, 0);
	publishKeyboard(0);
	const behavior: KeyboardAvoidingBehavior = "padding";
	const handles: TextInputHandle[] = [];
	const root = mockNode("root");
	const dispose = render(element(<SafeAreaView style={{ padding: 4 }}>
		<KeyboardAvoidingView behavior={behavior} keyboardVerticalOffset={20}>
			<TextInput value="draft" ref={(handle: TextInputHandle): void => {
				handles.push(handle);
			}} />
		</KeyboardAvoidingView>
	</SafeAreaView>), mockHost(), root as unknown as HostNode);
	const safe = root.children[0];
	const avoiding = safe.children[0];
	const input = avoiding.children[0];
	publishSafeArea(10, 0, 6, 0);
	publishKeyboard(100);
	assert (safe.style as Style).paddingTop === 14;
	assert (safe.style as Style).paddingBottom === 10;
	assert (avoiding.style as Style).paddingBottom === 80;
	assert handles.length === 1;
	handles[0].focus();
	assert handles[0].isFocused();
	handles[0].blur();
	assert !handles[0].isFocused();
	handles[0].clear();
	assert attrOf(input, "value") === "";
	dispose();
	let rejected = false;
	try { handles[0].clear(); } catch { rejected = true; }
	assert rejected;
	publishSafeArea(0, 0, 0, 0);
	publishKeyboard(0);
	assert (safe.style as Style).paddingTop === 14;
	assert (avoiding.style as Style).paddingBottom === 80;
}

test "public Modal toggles its overlay and releases it with render owner" {
	const [open, setOpen] = createSignal(false);
	const animation: ModalAnimationType = "none";
	const host = mockHost();
	const root = mockNode("root");
	const dispose = render(element(<View><Modal visible={open()} animationType={animation}>
		<Text>dialog</Text>
	</Modal></View>), host, root as unknown as HostNode);
	const overlay = overlayOf(host, root);
	assert overlay.children.length === 0;
	setOpen(true);
	flush();
	assert overlay.children.length === 1;
	assert overlay.children[0].tag === "modal";
	assert attrOf(overlay.children[0], "animationType") === "none";
	assert mockToString(overlay).indexOf("dialog") >= 0;
	assert mockToString(root).indexOf("dialog") < 0;
	setOpen(false);
	flush();
	assert overlay.children.length === 0;
	setOpen(true);
	flush();
	assert overlay.children.length === 1;
	dispose();
	setOpen(false);
	flush();
	setOpen(true);
	flush();
	assert overlay.children.length === 0;
}

interface ExportTone {
	name: string;
}

test "public Portal keeps context at a named mount and stops after disposal" {
	const Tone = createContext<ExportTone>({ name: "default" });
	const [width, setWidth] = createSignal<float64>(20);
	const root = mockNode("root");
	const target = mockNode("target");
	const dispose = render(element(<Tone value={{ name: "scoped" }}>
		<Portal mount={target as unknown as HostNode} style={{ width: width() }}>
			<Text>{useContext(Tone).name}</Text>
		</Portal>
	</Tone>), mockHost(), root as unknown as HostNode);
	assert mockToString(target) === "<target><view><text>scoped</text></view></target>";
	const container = target.children[0];
	setWidth(40);
	flush();
	assert (container.style as Style).width === 40;
	dispose();
	setWidth(60);
	flush();
	assert target.children.length === 0;
	assert (container.style as Style).width === 40;
}

test "public refresh switch indicator and neutral touchables reach mock host" {
	const [refreshing, setRefreshing] = createSignal(false);
	const [enabled, setEnabled] = createSignal(false);
	const size: IndicatorSize = "large";
	let presses: int32 = 0;
	const root = mockNode("root");
	const dispose = createRoot((release: () => void): () => void => {
		const stop = render(element(<View>
			<ScrollView refreshControl={<RefreshControl refreshing={refreshing()}
				onRefresh={(): void => { setRefreshing(true); }} />}>
				<Text>rows</Text>
			</ScrollView>
			<Switch value={enabled()} onValueChange={(value: boolean): void => {
				setEnabled(value);
				flush();
			}} />
			<ActivityIndicator size={size} animating={refreshing()} />
			<TouchableOpacity onPress={(): void => { presses += 1; }}>
				<Text>opacity</Text>
			</TouchableOpacity>
			<TouchableHighlight onPress={(): void => { presses += 1; }}>
				<Text>highlight</Text>
			</TouchableHighlight>
			<TouchableWithoutFeedback onPress={(): void => { presses += 1; }}>
				<Text>plain</Text>
			</TouchableWithoutFeedback>
		</View>), mockHost(), root as unknown as HostNode);
		return (): void => { stop(); release(); };
	});
	const children = root.children[0].children;
	assert children.length === 6;
	assert children[0].children.length === 1;
	assert attrOf(children[0], "refreshing") === "false";
	fireEvent(children[0], "onRefresh");
	flush();
	assert attrOf(children[0], "refreshing") === "true";
	assert attrOf(children[2], "animating") === "true";
	assert (children[2].style as Style).width === 36;
	const change = neonEvent("valuechange");
	change.value = "true";
	fireEventWith(children[1], "onValueChange", change);
	flush();
	assert enabled();
	assert attrOf(children[1], "value") === "true";
	for (let i = 3; i < 6; i++) {
		fireTouch(children[i], "onTouchStart", 10, 10, 7000 + i * 100);
		flush();
		fireTouch(children[i], "onTouchEnd", 10, 10, 7020 + i * 100);
		flush();
	}
	assert presses === 3;
	dispose();
	setRefreshing(false);
	flush();
	setEnabled(false);
	flush();
	assert attrOf(children[0], "refreshing") === "true";
	assert attrOf(children[1], "value") === "true";
}
