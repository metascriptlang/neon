import { createSignal, Accessor } from "../../../src/core/signal";
import { element } from "../../../src/macros/ui/element";
import { HostNode, MockNode, mockNode, mockHost, render, mockToString } from "../../../src/render/host";
import { Style } from "../../../src/render/style";
import { NeonNode } from "../../../src/render/node";
import { Show, For } from "../../../src/macros/ui/flow";
import {
	Svg,
	G,
	Path,
	Rect,
	Circle,
	Ellipse,
	Line,
	Polyline,
	Polygon,
	Text as SvgText,
	TSpan,
	Defs,
	LinearGradient,
	RadialGradient,
	Stop,
	ClipPath,
	Use,
} from "../../../src/components/svg/elements";

function mount(node: NeonNode): MockNode {
	const root: MockNode = mockNode("root");
	render(node, mockHost(), root as unknown as HostNode);
	return root;
}

function listOf(root: MockNode): string {
	const svg = root.children[0];
	for (const a of svg.attrs) {
		if (a.name === "displayList") { return a.value ?? ""; }
	}
	return "<none>";
}

const CIRCLE_40 = "M 90 50 C 90 72.0914 72.0914 90 50 90 C 27.9086 90 10 72.0914 10 50 C 10 27.9086 27.9086 10 50 10 C 72.0914 10 90 27.9086 90 50 Z";

test "one svg host node carries the shapes as a display list, sized by width and height" {
	const root = mount(element(<Svg width={100} height={80} accessibilityLabel="dot">
		<Circle cx={50} cy={50} r={40} fill="red" />
	</Svg>));
	assert root.children.length === 1 && root.children[0].tag === "svg" && root.children[0].children.length === 0, mockToString(root);
	const style = root.children[0].style as Style;
	assert style.width === 100 && style.height === 80, "size";
	assert listOf(root) === CIRCLE_40 + " F c 255 0 0 1 S n E 0 O", listOf(root);
	assert mockToString(root).indexOf("accessibilityLabel=\"dot\"") > 0, "label on the host node";
}

test "a reactive radius re-sends the list; an unchanged list is not re-sent" {
	const [r, setR] = createSignal<float64>(40);
	const [label, setLabel] = createSignal("a");
	const root = mount(element(<Svg width={100} height={100} accessibilityLabel={label()}>
		<Circle cx={50} cy={50} r={r()} fill="red" />
	</Svg>));
	setR(10);
	assert listOf(root).startsWith("M 60 50 C 60 55.5228 55.5228 60 50 60"), listOf(root);
	setLabel("b");
	setR(40);
	assert listOf(root).startsWith(CIRCLE_40), listOf(root);
}

test "a viewBox leads the list with its alignment" {
	const box = (aspect: string): string => listOf(mount(element(<Svg width={48} height={24} viewBox="0 0 24 24" preserveAspectRatio={aspect}>
		<Path d="M0 0 L24 24" stroke="black" />
	</Svg>)));
	assert box("").startsWith("V 0 0 24 24 5 0 M 0 0 L 24 24"), box("");
	assert box("xMinYMax slice").startsWith("V 0 0 24 24 7 1 "), box("xMinYMax slice");
	assert box("none").startsWith("V 0 0 24 24 0 0 "), box("none");
}

test "presentation is inherited from G and Svg; currentColor reads color" {
	const root = mount(element(<Svg width={10} height={10} color="#123456" stroke="currentColor" strokeWidth={3}>
		<G fill="none" strokeLinecap="round" strokeLinejoin="bevel">
			<Line x1={0} y1={0} x2={5} y2={5} />
			<Line x1={0} y1={5} x2={5} y2={0} strokeOpacity={0.5} />
		</G>
	</Svg>));
	assert listOf(root) === "M 0 0 L 5 5 F n S c 18 52 86 1 E 0 W 3 1 2 4 D 0 0 O M 0 5 L 5 0 F n S c 18 52 86 0.5 E 0 W 3 1 2 4 D 0 0 O", listOf(root);
}

test "G transform and opacity: a matrix op and a layer" {
	const root = mount(element(<Svg width={50} height={50}>
		<G transform="translate(10, 20) scale(2)" opacity={0.5}>
			<Rect width={10} height={10} stroke="#00f" strokeWidth={2} strokeDasharray={[2, 1, 1]} strokeDashoffset={1} fill="none" />
		</G>
		<G rotation={90} originX={5} originY={5}><Rect width={10} height={10} /></G>
	</Svg>));
	assert listOf(root) === "G 0.5 X 2 0 0 2 10 20 M 0 0 L 10 0 L 10 10 L 0 10 Z F n S c 0 0 255 1 E 0 W 2 0 0 4 D 6 2 1 1 2 1 1 1 O g " +
		"X 0 1 -1 0 10 0 M 0 0 L 10 0 L 10 10 L 0 10 Z F c 0 0 0 1 S n E 0 O", listOf(root);
}

test "rounded rect, ellipse, polyline from an array, polygon from a string, evenodd" {
	const root = mount(element(<Svg width={50} height={50}>
		<Rect x={0} y={0} width={20} height={10} rx={2} />
		<Ellipse cx={5} cy={5} rx={4} ry={2} fillRule="evenodd" />
		<Polyline points={[0, 0, 5, 5, 10, 0]} fill="none" stroke="black" />
		<Polygon points="0,0 5,5 10,0" fillOpacity="50%" />
	</Svg>));
	const list = listOf(root);
	assert list.startsWith("M 2 0 L 18 0 C 19.1046 0 20 0.8954 20 2 L 20 8 C 20 9.1046 19.1046 10 18 10 L 2 10 C 0.8954 10 0 9.1046 0 8 L 0 2 C 0 0.8954 0.8954 0 2 0 Z F c 0 0 0 1 S n E 0 O"), list;
	assert list.indexOf("M 9 5 C 9 6.1046 7.2091 7 5 7 C 2.7909 7 1 6.1046 1 5 C 1 3.8954 2.7909 3 5 3 C 7.2091 3 9 3.8954 9 5 Z F c 0 0 0 1 S n E 1 O") > 0, list;
	assert list.indexOf("M 0 0 L 5 5 L 10 0 F n S c 0 0 0 1 E 0 W 1 0 0 4 D 0 0 O") > 0, list;
	assert list.endsWith("M 0 0 L 5 5 L 10 0 Z F c 0 0 0 0.5 S n E 0 O"), list;
}

test "a shape with no paint or no area draws nothing; an unknown colour is an error" {
	const root = mount(element(<Svg width={50} height={50}>
		<Rect width={0} height={10} />
		<Circle r={5} fill="none" />
		<Circle cx={1} cy={1} r={1} fill="transparent" />
	</Svg>));
	assert listOf(root) === "M 2 1 C 2 1.5523 1.5523 2 1 2 C 0.4477 2 0 1.5523 0 1 C 0 0.4477 0.4477 0 1 0 C 1.5523 0 2 0.4477 2 1 Z F c 0 0 0 0 S n E 0 O", listOf(root);
	let message = "";
	try {
		mount(element(<Svg width={5} height={5}><Rect width={5} height={5} fill="blurple" /></Svg>));
	} catch (e) {
		message = e.message;
	}
	assert message.indexOf("blurple") >= 0, "error: " + message;
}

test "linear gradient in bounding-box units, radial in user space, missing url falls back" {
	const root = mount(element(<Svg width={200} height={100}>
		<Defs>
			<LinearGradient id="sky" x1="0" y1="0" x2="1" y2="0">
				<Stop offset={0} stopColor="#ff0000" />
				<Stop offset="100%" stopColor="blue" stopOpacity={0.5} />
			</LinearGradient>
			<RadialGradient id="glow" cx={50} cy={50} r={50} gradientUnits="userSpaceOnUse">
				<Stop offset={0.2} stopColor="white" />
				<Stop offset={0.1} stopColor="black" />
			</RadialGradient>
		</Defs>
		<Rect x={10} y={20} width={100} height={50} fill="url(#sky)" />
		<Rect width={10} height={10} fill="url(#glow)" />
		<Rect width={10} height={10} fill="url(#nothing) green" stroke="url(#nothing)" />
	</Svg>));
	const list = listOf(root);
	assert list.indexOf("F l 100 0 0 50 10 20 0 0 1 0 2 0 255 0 0 1 1 0 0 255 0.5") > 0, list;
	assert list.indexOf("F r 1 0 0 1 0 0 50 50 50 50 50 2 0.2 255 255 255 1 0.2 0 0 0 1") > 0, list;
	assert list.endsWith("F c 0 128 0 1 S n E 0 O"), list;
}

test "clip path wraps what it clips; use repeats a shape" {
	const root = mount(element(<Svg width={50} height={50}>
		<Defs>
			<ClipPath id="half"><Rect width={5} height={10} /></ClipPath>
			<Circle id="dot" r={1} />
		</Defs>
		<Rect width={10} height={10} clipPath="url(#half)" />
		<Use href="#dot" x={20} y={30} fill="red" />
	</Svg>));
	const list = listOf(root);
	assert list.startsWith("M 0 0 L 5 0 L 5 10 L 0 10 Z E 0 K M 0 0 L 10 0 L 10 10 L 0 10 Z F c 0 0 0 1 S n E 0 O k X 1 0 0 1 20 30 M 1 0 C"), list;
	assert list.endsWith("Z F c 255 0 0 1 S n E 0 O"), list;
}

test "text runs: position, anchor, tspans continue or move, escaped text" {
	const root = mount(element(<Svg width={100} height={40}>
		<SvgText x={10} y={20} fontSize={14} textAnchor="middle" fill="#000">Hi there<TSpan dx={4} fontWeight="bold" fill="red">you</TSpan></SvgText>
		<SvgText y={30}><TSpan x={5}>a+b%</TSpan></SvgText>
	</Svg>));
	assert listOf(root) === "T 1 2 1 10 1 20 0 0 14 0 0 0 0 1 Hi%20there 0 0 0 0 4 0 14 1 255 0 0 1 you " +
		"T 0 1 1 5 1 30 0 0 12 0 0 0 0 1 a%2Bb%25", listOf(root);
}

test "Show and For inside an Svg add and remove shapes" {
	const [on, setOn] = createSignal(false);
	const [bars, setBars] = createSignal<float64[]>([10, 20]);
	const root = mount(element(<Svg width={50} height={50}>
		<Show when={on()}><Rect width={5} height={5} fill="red" /></Show>
		<For each={bars()}>{(h: float64, i: Accessor<number>): NeonNode => element(<Rect width={2} height={h} fill="blue" />)}</For>
	</Svg>));
	assert listOf(root) === "M 0 0 L 2 0 L 2 10 L 0 10 Z F c 0 0 255 1 S n E 0 O M 0 0 L 2 0 L 2 20 L 0 20 Z F c 0 0 255 1 S n E 0 O", listOf(root);
	setOn(true);
	assert listOf(root).startsWith("M 0 0 L 5 0 L 5 5 L 0 5 Z F c 255 0 0 1"), listOf(root);
	setBars([30]);
	assert listOf(root).endsWith("M 0 0 L 2 0 L 2 30 L 0 30 Z F c 0 0 255 1 S n E 0 O"), listOf(root);
	assert listOf(root).indexOf("L 2 20") < 0, listOf(root);
}
