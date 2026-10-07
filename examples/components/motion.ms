import { createSignal } from "../../src/core/signal";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { For } from "../../src/macros/ui/flow";
import { NeonNode } from "../../src/render/node";
import { NeonEvent } from "../../src/render/event";
import { View, Text, Pressable, ScrollView } from "../../src/components/primitives";
import {
	Animated, AnimatedValue, AnimatedNode, Easing, EndResult, LayoutAnimation, Presence, CompositeAnimation,
} from "../../src/animation/index";

const styles = createStyles({
	screen: { flex: 1, flexDirection: "column", backgroundColor: "#1e1e2e" },
	header: { backgroundColor: "#313244", justifyContent: "flex-end", paddingLeft: 16, paddingBottom: 8 },
	title: { color: "#cdd6f4", fontSize: 22, fontWeight: "bold" },
	status: { color: "#89b4fa", fontSize: 14 },
	scroll: { flex: 1 },
	content: { flexDirection: "column", gap: 12, padding: 16 },
	controls: { flexDirection: "row", flexWrap: "wrap", gap: 8 },
	button: { padding: 10, backgroundColor: "#45475a", color: "#cdd6f4" },
	stage: { height: 90, flexDirection: "row", alignItems: "center", gap: 16 },
	box: { width: 80, height: 80, backgroundColor: "#f38ba8", justifyContent: "center", alignItems: "center" },
	card: { width: 120, height: 70, backgroundColor: "#a6e3a1", justifyContent: "center", alignItems: "center" },
	spinner: { width: 60, height: 60, backgroundColor: "#fab387", justifyContent: "center", alignItems: "center" },
	label: { color: "#11111b", fontSize: 14 },
	panel: { backgroundColor: "#45475a", overflow: "hidden" },
	panelText: { color: "#cdd6f4", padding: 12 },
	toast: { padding: 12, backgroundColor: "#89b4fa" },
	row: { height: 48, padding: 12, backgroundColor: "#181825", color: "#a6adc8" },
});

function rows(): number[] {
	const out: number[] = [];
	for (let i = 1; i <= 30; i += 1) { out.push(i); }
	return out;
}

export function Motion(): NeonNode {
	const fade = new AnimatedValue(1);
	const [fadeState, setFadeState] = createSignal("fade 1");
	const slide = new AnimatedValue(0);
	const [springState, setSpringState] = createSignal("spring 0");
	const spin = new AnimatedValue(0);
	const scrollY = new AnimatedValue(0);
	const [scrolled, setScrolled] = createSignal<number>(0);
	const [expanded, setExpanded] = createSignal(false);
	const [toast, setToast] = createSignal(false);

	const rotation: AnimatedNode = spin.interpolate({ inputRange: [0, 1], outputRange: [0, 360] });
	const headerHeight: AnimatedNode = scrollY.interpolate({ inputRange: [0, 120], outputRange: [110, 56], extrapolate: "clamp" });
	const titleOpacity: AnimatedNode = scrollY.interpolate({ inputRange: [0, 120], outputRange: [1, 0.4], extrapolate: "clamp" });

	const spinLoop: CompositeAnimation = Animated.loop(Animated.timing(spin, { toValue: 1, duration: 1200, easing: Easing.linear }));
	spinLoop.start();

	const toggleFade = (e: NeonEvent): void => {
		const target = fade.peek() > 0.5 ? 0 : 1;
		setFadeState("fade moving");
		Animated.timing(fade, { toValue: target, duration: 800, easing: Easing.inOut(Easing.quad) }).start((r: EndResult): void => {
			if (r.finished) { setFadeState("fade " + target.toString()); }
		});
	};
	const pushCard = (e: NeonEvent): void => {
		const target = slide.peek() > 50 ? 0 : 160;
		setSpringState("spring moving");
		Animated.spring(slide, { toValue: target, friction: 4, tension: 40 }).start((r: EndResult): void => {
			if (r.finished) { setSpringState("spring " + target.toString()); }
		});
	};
	const togglePanel = (e: NeonEvent): void => {
		LayoutAnimation.configureNext(LayoutAnimation.create(500, "easeInEaseOut", "opacity"));
		setExpanded(!expanded());
	};

	return <View style={styles.screen}>
		<Animated.View style={[styles.header, { height: headerHeight.get() }]}>
			<Animated.Text style={[styles.title, { opacity: titleOpacity.get() }]}>Neon motion</Animated.Text>
		</Animated.View>
		<ScrollView style={styles.scroll} scrollEventThrottle={16}
			onScroll={Animated.event({ y: scrollY }, { listener: (e: NeonEvent): void => { setScrolled(Math.round(e.y)); } })}>
			<View style={styles.content}>
				<Text style={styles.status}>{fadeState() + " · " + springState() + " · scroll " + scrolled().toString()}</Text>
				<View style={styles.controls}>
					<Pressable style={styles.button} onPress={toggleFade}>fade</Pressable>
					<Pressable style={styles.button} onPress={pushCard}>spring</Pressable>
					<Pressable style={styles.button} onPress={togglePanel}>{expanded() ? "collapse" : "expand"}</Pressable>
					<Pressable style={styles.button} onPress={() => setToast(!toast())}>toast</Pressable>
				</View>
				<View style={styles.stage}>
					<Animated.View style={[styles.box, { opacity: fade.get() }]}><Text style={styles.label}>fade box</Text></Animated.View>
					<Animated.View style={[styles.spinner, { transform: `rotate(${rotation.get()}deg)` }]}><Text style={styles.label}>spin</Text></Animated.View>
				</View>
				<View style={styles.stage}>
					<Animated.View style={[styles.card, { transform: `translateX(${slide.get()}px)` }]}><Text style={styles.label}>spring card</Text></Animated.View>
				</View>
				<View style={[styles.panel, { height: expanded() ? 160 : 0 }]}>
					<Text style={styles.panelText}>panel body</Text>
				</View>
				<Text style={styles.status}>after panel</Text>
				<Presence when={toast()} type="slide-up" duration={300}>
					<View style={styles.toast}><Text style={styles.label}>toast shown</Text></View>
				</Presence>
				<For each={rows()}>{(row: number): NeonNode => <Text style={styles.row}>{"row " + row.toString()}</Text>}</For>
			</View>
		</ScrollView>
	</View>;
}
