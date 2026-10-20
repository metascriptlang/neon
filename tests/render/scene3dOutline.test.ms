import { Accessor, createSignal } from "../../src/core/signal";
import { createRoot } from "../../src/core/owner";
import { flush, resetErrorHalt } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { Errored } from "../../src/macros/ui/flow";
import { NeonNode } from "../../src/render/node";
import { HostNode, mockHost, mockNode, render } from "../../src/render/host";
import { Void, View, Text } from "../../src/components/primitives";
import { Scene3D, Scene3DHandle } from "../../src/components/scene3d";
import { ForwardOutlineSettings, defaults } from "../../../void/src/void3d/forwardOutline";
import { reserveUniforms, releaseUniforms } from "../../../void/src/void3d/draw";
import { UniformBlock } from "../../../void/src/void3d/material";
import { MATERIAL_UNIFORM_SLOT } from "../../../void/src/void3d/gpu3d";
import { freeRanges } from "../../../void/src/void3d/uniformPool";

function invalid(blend: float32, settings: ForwardOutlineSettings): string {
	let message = "";
	createRoot((dispose: () => void): void => {
		try {
			const root = mockNode("root");
			element(<Void><Scene3D outlineBlend={blend} outlineSettings={settings} /></Void>)(mockHost(), root as unknown as HostNode, null);
		} catch (error) { message = error.toString(); }
		finally { dispose(); resetErrorHalt(); }
	});
	return message;
}

test "forward outline allocates its existing CPU blocks once and disabled scenes reserve none" {
	const [blend, setBlend] = createSignal<float32>(0.0);
	const refs: Scene3DHandle[] = [];
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene3D outlineBlend={blend()}
		ref={(handle: Scene3DHandle): void => { refs.push(handle); }} /></Void>), mockHost(), root as unknown as HostNode);
	try {
		const pool = refs[0].context.uniforms;
		const initial = pool.used;
		setBlend(0.5); flush();
		assert pool.used === initial + 20;
		setBlend(0.0); flush();
		assert pool.used === initial + 20;
		setBlend(1.0); flush();
		assert pool.used === initial + 20 && refs.length === 1;
	} finally { dispose(); }
	assert refs[0].context.closed && refs[0].context.uniforms.closed && refs[0].scene.closed;
}

test "reactive outline settings and blend wake only their own area and effects stop on disposal" {
	const [blend, setBlend] = createSignal<float32>(0.0);
	const [settings, setSettings] = createSignal<ForwardOutlineSettings>(ForwardOutlineSettings.defaults());
	const refs: Scene3DHandle[] = [];
	const root = mockNode("root");
	const dispose = render(element(<View>
		<Void><Scene3D outlineBlend={blend()} outlineSettings={settings()}
			ref={(handle: Scene3DHandle): void => { refs.push(handle); }} /></Void>
		<Void><Scene3D /></Void>
	</View>), mockHost(), root as unknown as HostNode);
	const first = root.children[0].children[0];
	const sibling = root.children[0].children[1];
	try {
		const siblingRequests = sibling.attrs.length;
		let requested = first.attrs.length;
		setSettings({ ...ForwardOutlineSettings.defaults(), pixelWidth: 4.0 }); flush();
		assert first.attrs.length > requested && sibling.attrs.length === siblingRequests;
		requested = first.attrs.length;
		setBlend(0.75); flush();
		assert first.attrs.length > requested && sibling.attrs.length === siblingRequests;
	} finally { dispose(); }
	const requested = first.attrs.length;
	setBlend(0.25); setSettings(ForwardOutlineSettings.defaults()); flush();
	assert first.attrs.length === requested && refs[0].context.closed;
}

test "forward outline refuses invalid blend and settings by component name before Void panics" {
	const normal = ForwardOutlineSettings.defaults();
	assert invalid(-0.1, normal).includes("Scene3D: outlineBlend must be finite and in [0,1]");
	assert invalid(1.1, normal).includes("Scene3D: outlineBlend must be finite and in [0,1]");
	assert invalid(0.5, { ...normal, pixelWidth: 0.0 }).includes("Scene3D: invalid outlineSettings");
	assert invalid(0.5, { ...normal, normalThreshold: 2.0 }).includes("Scene3D: invalid outlineSettings");
}

test "outline capacity refusal reaches Errored and reset retries the same scene after free ranges return" {
	const [blend, setBlend] = createSignal<float32>(0.0);
	const refs: Scene3DHandle[] = [];
	const resets: (() => void)[] = [];
	const errors: Error[] = [];
	const held: UniformBlock[] = [];
	const root = mockNode("root");
	const dispose = render(element(<Void>{Errored({
		children: element(<Scene3D outlineBlend={blend()} ref={(handle: Scene3DHandle): void => { refs.push(handle); }} />),
		fallback: (error: Accessor<Error>, reset: () => void): NeonNode => {
			errors.push(error()); resets.push(reset); return element(<Text>capacity</Text>);
		},
	})}</Void>), mockHost(), root as unknown as HostNode);
	const context = refs[0].context;
	const fill = (length: int32): void => {
		const reserved = reserveUniforms(context, MATERIAL_UNIFORM_SLOT, length);
		if (!reserved.ok) { throw new Error("outline fixture: cannot fill pool"); }
		held.push(reserved.value);
	};
	const release = (): void => {
		while (held.length > 0) {
			const block = held.pop();
			assert releaseUniforms(context, block).ok;
		}
	};
	try {
		fill(4);
		while (context.uniforms.values.length - context.uniforms.used >= 8) { fill(8); }
		const remaining = context.uniforms.values.length - context.uniforms.used;
		if (remaining > 0) { fill(remaining as int32); }
		const used = context.uniforms.used;
		setBlend(0.5); flush();
		assert errors.length === 1 && errors[0].toString().includes("Scene3D: outlineBlend needs additional uniform capacity");
		assert refs.length === 1 && !context.closed && !refs[0].scene.closed;
		assert context.uniforms.used === used;
		release();
		const available = context.uniforms.freeRanges();
		resets[0](); flush();
		assert refs.length === 1 && !context.closed && errors.length === 1;
		assert context.uniforms.freeRanges() === available - 3, "reset must reserve the outline blocks before any new prop change";
		const first = root.children[0];
		const requested = first.attrs.length;
		setBlend(0.75); flush();
		assert first.attrs.length > requested && context.uniforms.used === used;
		assert context.uniforms.freeRanges() === available - 3, "later blend updates must reuse the blocks reserved during reset";
	} finally {
		release(); dispose(); resetErrorHalt();
	}
	assert context.closed;
}
