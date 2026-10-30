import { accessor, createSignal } from "../../src/core/signal";
import { flush } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { Show } from "../../src/macros/ui/flow";
import { HostNode, mockNode, mockHost, render } from "../../src/render/host";
import { Void } from "../../src/components/primitives";
import { Scene2D, Group, Rect } from "../../src/components/scene2d";
import {
	NodeRef, Scene2D as VoidScene2D, filterChain, paint, colorMatrix, isLive,
} from "../../../void/src/void2d/node";
import {
	Filter, FilterKind, rgba, noFilter, blurFilter, glowFilter, dropShadowFilter,
} from "../../../void/src/void2d/types";
import { Mat4 } from "../../../void/src/math/math3d";
import {
	NO_COLOR_MATRIX, colorMatrixGrayscale, colorMatrixAlphaOnly,
} from "../../../void/src/void2d/effect";

function soleFilter(n: NodeRef): Filter {
	const steps = n.filterChain().steps;
	if (steps.length > 1) { throw new Error(`a filter prop sets one step, and this node holds ${steps.length}`); }
	return steps.length === 0 ? noFilter() : steps[0];
}

test "raw filters replace every Void kind without remounting or changing sibling filters" {
	const scenes: VoidScene2D[] = [];
	const nodes: NodeRef[] = [];
	const [value, setValue] = createSignal<Filter>(blurFilter(2.0));
	const [shown, setShown] = createSignal(true);
	let reads: int32 = 0;
	const readFilter = (): Filter => { reads += 1; return value(); };
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene2D
		ref={(scene: VoidScene2D): void => { scenes.push(scene); }}>
		{Show({ when: accessor(() => shown()), children: element(
			<Group filter={readFilter()}
				ref={(node: NodeRef): void => { nodes.push(node); }}>
				<Rect width={4.0} height={5.0} color={rgba(1.0, 1.0, 1.0, 1.0)}
					ref={(node: NodeRef): void => { nodes.push(node); }} />
			</Group>
		) })}
		<Rect width={2.0} height={3.0} color={rgba(1.0, 1.0, 1.0, 1.0)}
			ref={(node: NodeRef): void => { nodes.push(node); }} />
	</Scene2D></Void>), mockHost(), root as unknown as HostNode);
	try {
		const id = nodes[0].id;
		assert soleFilter(nodes[0]).kind === FilterKind.Blur;
		assert soleFilter(nodes[0]) === blurFilter(2.0);
		let copy = soleFilter(nodes[0]);
		copy.radius = 99.0;
		assert soleFilter(nodes[0]).radius === 2.0;
		setValue(glowFilter(rgba(0.2, 0.4, 0.6, 0.8), 7.0, 0.5));
		flush();
		assert soleFilter(nodes[0]).kind === FilterKind.Glow;
		assert soleFilter(nodes[0]) === value();
		setValue(dropShadowFilter(rgba(0.1, 0.3, 0.5, 0.7), 4.0, -6.0, 8.0));
		flush();
		assert soleFilter(nodes[0]).kind === FilterKind.DropShadow;
		assert soleFilter(nodes[0]) === value();
		assert nodes[0].id === id && nodes.length === 3;
		assert soleFilter(nodes[1]) === noFilter() && soleFilter(nodes[2]) === noFilter();
		setValue(noFilter());
		flush();
		assert soleFilter(nodes[0]).kind === FilterKind.None;
		assert soleFilter(nodes[0]) === noFilter();
		setShown(false);
		flush();
		assert !nodes[0].isLive() && !nodes[1].isLive() && nodes[2].isLive();
		const stopped = reads;
		setValue(glowFilter(rgba(0.8, 0.6, 0.4, 0.2), 9.0, 2.0));
		flush();
		assert reads === stopped;
		setShown(true);
		flush();
		assert nodes.length === 5 && soleFilter(nodes[3]) === value();
		assert soleFilter(nodes[4]) === noFilter();
	} finally { dispose(); }
	const stopped = reads;
	setValue(blurFilter(11.0)); setShown(false);
	flush();
	assert reads === stopped && scenes[0].closed;
	for (const node of nodes) { assert !node.isLive(); }
}

test "filter replacement preserves independent color matrix rows and releases them on removal" {
	const scenes: VoidScene2D[] = [];
	const nodes: NodeRef[] = [];
	const [matrix, setMatrix] = createSignal<Mat4>(colorMatrixGrayscale(1.0));
	const [value, setValue] = createSignal<Filter>(blurFilter(3.0));
	const [shown, setShown] = createSignal(true);
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene2D
		ref={(scene: VoidScene2D): void => { scenes.push(scene); }}>
		{Show({ when: accessor(() => shown()), children: element(
			<Rect width={4.0} height={5.0} color={rgba(1.0, 1.0, 1.0, 1.0)}
				filter={value()} colorMatrix={matrix()}
				ref={(node: NodeRef): void => { nodes.push(node); }} />
		) })}
		<Rect width={2.0} height={3.0} color={rgba(1.0, 1.0, 1.0, 1.0)}
			colorMatrix={colorMatrixAlphaOnly(0.75)}
			ref={(node: NodeRef): void => { nodes.push(node); }} />
	</Scene2D></Void>), mockHost(), root as unknown as HostNode);
	const scene = scenes[0];
	try {
		const first = nodes[0].paint().colorMatrixRow;
		const second = nodes[1].paint().colorMatrixRow;
		assert first >= 0 && second >= 0 && first !== second;
		assert scene.colorMatrices.length === 2;
		assert soleFilter(nodes[0]) === blurFilter(3.0);
		setValue(dropShadowFilter(rgba(0.1, 0.2, 0.3, 0.4), 6.0, 7.0, -8.0));
		flush();
		assert soleFilter(nodes[0]) === value();
		assert nodes[0].paint().colorMatrixRow === first;
		assert nodes[0].colorMatrix() === colorMatrixGrayscale(1.0);
		setMatrix(colorMatrixAlphaOnly(0.25));
		flush();
		assert nodes[0].paint().colorMatrixRow === first;
		assert nodes[0].colorMatrix() === colorMatrixAlphaOnly(0.25);
		assert soleFilter(nodes[0]) === value();
		assert nodes[1].paint().colorMatrixRow === second;
		assert nodes[1].colorMatrix() === colorMatrixAlphaOnly(0.75);
		assert soleFilter(nodes[1]) === noFilter();
		setMatrix(NO_COLOR_MATRIX);
		flush();
		assert nodes[0].paint().colorMatrixRow === -1;
		assert scene.freeColorMatrices.length === 1;
		setMatrix(colorMatrixGrayscale(0.5));
		flush();
		assert nodes[0].paint().colorMatrixRow === first;
		assert scene.colorMatrices.length === 2 && scene.freeColorMatrices.length === 0;
		setShown(false);
		flush();
		assert !nodes[0].isLive() && scene.freeColorMatrices.length === 1;
		assert nodes[1].isLive() && nodes[1].paint().colorMatrixRow === second;
		setMatrix(colorMatrixAlphaOnly(0.5)); setValue(noFilter()); setShown(true);
		flush();
		assert nodes[2].paint().colorMatrixRow === first;
		assert nodes[2].colorMatrix() === colorMatrixAlphaOnly(0.5);
		assert soleFilter(nodes[2]) === noFilter();
	} finally { dispose(); }
	setMatrix(colorMatrixGrayscale(1.0)); setValue(blurFilter(8.0));
	flush();
	assert scene.closed;
	for (const node of nodes) { assert !node.isLive(); }
}
