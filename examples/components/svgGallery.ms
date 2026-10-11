// react-native-svg's everyday uses on Neon: an icon row, a donut chart, a line chart with a
// gradient area, a progress ring driven by Animated, and a logo from an SVG document.

import { Accessor, createSignal } from "../../src/core/signal";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { For } from "../../src/macros/ui/flow";
import { NeonNode } from "../../src/render/node";
import { NeonEvent } from "../../src/render/event";
import { View, Text, Pressable } from "../../src/components/primitives";
import { Animated, Easing, EndResult, useAnimatedValue } from "../../src/animation/index";
import {
	Svg,
	G,
	Path,
	Circle,
	Polyline,
	Text as SvgText,
	Defs,
	LinearGradient,
	Stop,
} from "../../src/components/svg/elements";
import { SvgXml } from "../../src/components/svg/xml";

const styles = createStyles({
	screen: { flex: 1, backgroundColor: "#ffffff", paddingTop: 56, paddingLeft: 12, paddingRight: 12, gap: 10 },
	title: { color: "#1c1b1f", fontSize: 20, fontWeight: "bold" },
	status: { color: "#6750a4", fontSize: 15 },
	row: { flexDirection: "row", alignItems: "center", gap: 12 },
	button: { paddingTop: 8, paddingBottom: 8, paddingLeft: 14, paddingRight: 14, backgroundColor: "#6750a4", borderRadius: 8 },
	buttonText: { color: "#ffffff", fontSize: 15 },
});

interface Icon {
	name: string;
	color: string;
	d: string;
}

// Material Design icons (Apache 2.0), 24×24.
const ICONS: Icon[] = [
	{ name: "heart", color: "#e53935", d: "M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z" },
	{ name: "star", color: "#fbc02d", d: "M12 17.27L18.18 21l-1.64-7.03L22 9.24l-7.19-.61L12 2 9.19 8.63 2 9.24l5.46 4.73L5.82 21z" },
	{ name: "check", color: "#43a047", d: "M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z" },
	{ name: "home", color: "#1e88e5", d: "M10 20v-6h4v6h5v-8h3L12 3 2 12h3v8z" },
];

interface Slice {
	value: float64;
	color: string;
}

const SLICES: Slice[] = [
	{ value: 40, color: "#e53935" },
	{ value: 30, color: "#1e88e5" },
	{ value: 20, color: "#43a047" },
	{ value: 10, color: "#fbc02d" },
];

const SALES: float64[] = [20, 45, 30, 70, 55, 90, 75, 100];

const LOGO = "<svg viewBox=\"0 0 200 60\"><defs><linearGradient id=\"brand\" x1=\"0\" y1=\"0\" x2=\"1\" y2=\"0\">" +
	"<stop offset=\"0\" stop-color=\"#ff6f00\"/><stop offset=\"1\" stop-color=\"#6a1b9a\"/></linearGradient></defs>" +
	"<rect width=\"200\" height=\"60\" rx=\"12\" fill=\"url(#brand)\"/>" +
	"<text x=\"100\" y=\"40\" font-size=\"28\" font-weight=\"bold\" fill=\"#ffffff\" text-anchor=\"middle\">NEON</text></svg>";

function point(cx: float64, cy: float64, r: float64, degrees: float64): string {
	const a = degrees * Math.PI / 180;
	return `${cx + r * Math.cos(a)} ${cy + r * Math.sin(a)}`;
}

// One donut slice from `start` to `end` degrees, clockwise from three o'clock.
export function arcPath(cx: float64, cy: float64, r: float64, start: float64, end: float64): string {
	const large = end - start > 180 ? 1 : 0;
	return `M ${point(cx, cy, r, start)} A ${r} ${r} 0 ${large} 1 ${point(cx, cy, r, end)}`;
}

function donutSlices(): string[] {
	let total = 0.0;
	for (const s of SLICES) { total += s.value; }
	const paths: string[] = [];
	let at = -90.0;
	for (const s of SLICES) {
		const sweep = s.value / total * 360;
		paths.push(arcPath(70, 70, 50, at, at + sweep));
		at += sweep;
	}
	return paths;
}

function chartPoints(): string {
	let text = "";
	for (let i = 0; i < SALES.length; i += 1) {
		text += `${(i as float64) * 54 + 1} ${110 - SALES[i]} `;
	}
	return text.trim();
}

const RING = 2 * Math.PI * 50;

export function SvgGallery(): NeonNode {
	const progress = useAnimatedValue(0);
	const [status, setStatus] = createSignal("status progress 0%");
	const slices = donutSlices();
	const linePoints = chartPoints();
	const area = `M 1 120 L ${linePoints.split(" ").join(" ")} L 379 120 Z`;
	const animate = (e: NeonEvent): void => {
		const target = progress.peek() > 0.5 ? 0 : 0.75;
		setStatus("status progress moving");
		Animated.timing(progress, { toValue: target, duration: 600, easing: Easing.inOut(Easing.quad) }).start((r: EndResult): void => {
			if (r.finished) { setStatus(`status progress ${Math.round(target * 100)}%`); }
		});
	};
	return <View style={styles.screen}>
		<Text style={styles.title}>Neon SVG</Text>
		<Text style={styles.status}>{status()}</Text>
		<View style={styles.row}>
			<For each={ICONS}>{(icon: Icon, i: Accessor<number>): NeonNode => <Svg width={40} height={40} viewBox="0 0 24 24" accessibilityLabel={"icon " + icon.name}>
				<Path d={icon.d} fill={icon.color} />
			</Svg>}</For>
		</View>
		<View style={styles.row}>
			<Svg width={140} height={140} accessibilityLabel="donut chart">
				<G fill="none" strokeWidth={24}>
					<Path d={slices[0]} stroke={SLICES[0].color} />
					<Path d={slices[1]} stroke={SLICES[1].color} />
					<Path d={slices[2]} stroke={SLICES[2].color} />
					<Path d={slices[3]} stroke={SLICES[3].color} />
				</G>
			</Svg>
			<Svg width={140} height={140} accessibilityLabel="progress ring">
				<Circle cx={70} cy={70} r={50} stroke="#e0e0e0" strokeWidth={12} fill="none" />
				<Circle cx={70} cy={70} r={50} stroke="#8e24aa" strokeWidth={12} fill="none" strokeLinecap="round"
					strokeDasharray={[RING, RING]} strokeDashoffset={RING * (1 - progress.get())}
					strokeOpacity={progress.get() > 0.001 ? 1.0 : 0.0} rotation={-90} originX={70} originY={70} />
				<SvgText x={70} y={78} fontSize={24} fontWeight="bold" textAnchor="middle" fill="#8e24aa">{`${Math.round(progress.get() * 100)}%`}</SvgText>
			</Svg>
		</View>
		<Pressable style={styles.button} onPress={animate}><Text style={styles.buttonText}>animate</Text></Pressable>
		<Svg width={380} height={120} accessibilityLabel="line chart">
			<Defs>
				<LinearGradient id="area" x1="0" y1="0" x2="0" y2="1">
					<Stop offset={0} stopColor="#1e88e5" stopOpacity={0.6} />
					<Stop offset={1} stopColor="#1e88e5" stopOpacity={0.1} />
				</LinearGradient>
			</Defs>
			<Path d={area} fill="url(#area)" />
			<Polyline points={linePoints} fill="none" stroke="#1e88e5" strokeWidth={3} strokeLinejoin="round" />
		</Svg>
		<SvgXml xml={LOGO} width={200} height={60} accessibilityLabel="logo" />
	</View>;
}
