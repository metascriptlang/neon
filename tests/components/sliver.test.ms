import { createRoot } from "../../src/core/owner";
import { createSignal, Accessor } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { neonEvent } from "../../src/render/event";
import { NeonNode } from "../../src/render/node";
import { HostNode, MockNode, mockNode, mockHost, render, fireEventWith } from "../../src/render/host";
import { Text, View, ScrollView } from "../../src/components/primitives";
import {
	CollapsingHeader,
	CustomScrollView,
	FloatingOffset,
	backgroundOpacity,
	createScrollOffset,
	headerMetrics,
	sliverGrid,
	sliverList,
	sliverPinnedHeader,
	sliverToBox,
} from "../../src/components/sliver";

function texts(n: MockNode, out: string[]): string[] {
	if (n.tag === "" && n.text !== "") { out.push(n.text); }
	for (const k of n.children) { texts(k, out); }
	return out;
}

test "a pinned header shrinks from its expanded to its collapsed height and stays" {
	const a = headerMetrics(0, 200, 56, true);
	assert a.extent === 200 && a.translate === 0 && a.progress === 0, "expanded at rest";
	const b = headerMetrics(100, 200, 56, true);
	assert b.extent === 100 && b.translate === 0, "half way: " + b.extent.toString();
	const c = headerMetrics(500, 200, 56, true);
	assert c.extent === 56 && c.translate === 0 && c.progress === 1, "collapsed and pinned";
}

test "a scrolling header collapses, then slides away with the content" {
	const a = headerMetrics(150, 200, 56, false);
	assert a.extent === 56 && a.translate === -6, "starts sliding once collapsed: " + a.translate.toString();
	const b = headerMetrics(300, 200, 56, false);
	assert b.translate === -56, "gone: " + b.translate.toString();
}

test "a floating header comes back as soon as the user scrolls back" {
	const f = new FloatingOffset();
	assert f.update(300, 200) === 200, "scrolled away";
	assert f.update(1000, 200) === 200, "stays away";
	assert f.update(950, 200) === 150, "50 back shows 50";
	assert f.update(1000, 200) === 200, "forward hides it again";
}

test "the background fades over the last toolbar height of the collapse" {
	assert backgroundOpacity(0, 256, 56) === 1, "opaque expanded";
	assert backgroundOpacity(0.5, 256, 56) === 1, "still opaque before the fade starts";
	assert Math.abs(backgroundOpacity(0.86, 256, 56) - 0.5) < 0.01, "half faded: " + backgroundOpacity(0.86, 256, 56).toString();
	assert backgroundOpacity(1, 256, 56) === 0, "gone collapsed";
}

test "a CollapsingHeader follows a ScrollView's offset through createScrollOffset" {
	const root = mockNode("root");
	const scroll = createScrollOffset(false);
	createRoot((): void => {
		render(element(<View>
			<ScrollView onScroll={scroll.onScroll}><View style={{ height: 2000 }} /></ScrollView>
			<CollapsingHeader scrollOffset={scroll.offset} expandedHeight={200} collapsedHeight={56} pinned={true} title={<Text>Inbox</Text>} />
		</View>), mockHost(), root as unknown as HostNode);
	});
	const header = root.children[0].children[1];
	const height = (): number => {
		const s = header.style;
		return s === null || s.height === null ? -1 : s.height as number;
	};
	assert height() === 200, "expanded: " + height().toString();
	const e = neonEvent("scroll");
	e.y = 120;
	fireEventWith(root.children[0].children[0], "onScroll", e);
	assert height() === 80, "follows the offset: " + height().toString();
}

test "a CustomScrollView lays a box, a pinned header, a list and a grid end to end in one list" {
	const root = mockNode("root");
	const [songs, setSongs] = createSignal<string[]>(["a", "b"]);
	const [photos, setPhotos] = createSignal<string[]>(["p1", "p2", "p3"]);
	createRoot((): void => {
		render(CustomScrollView({
			slivers: [
				sliverToBox(element(<Text>banner</Text>)),
				sliverPinnedHeader(element(<Text>Songs</Text>)),
				sliverList<string>(songs, (s: string, i: Accessor<number>): NeonNode => element(<Text>{"song " + s}</Text>)),
				sliverGrid<string>(photos, 2, (p: string, i: Accessor<number>): NeonNode => element(<Text>{"photo " + p}</Text>), null),
			],
		}), mockHost(), root as unknown as HostNode);
	});
	assert texts(root, []).join(",") === "banner,Songs,song a,song b,photo p1,photo p2,photo p3", "in order: " + texts(root, []).join(",");
	setSongs(["a", "b", "c"]);
	assert texts(root, []).join(",") === "banner,Songs,song a,song b,song c,photo p1,photo p2,photo p3", "a list grows in place: " + texts(root, []).join(",");
}
