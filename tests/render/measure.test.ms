import { HostNode, mockHost, mockNode } from "../../src/render/host";
import { MeasureRect, MeasureError } from "../../src/render/hostTypes";
import { ElementHandle } from "../../src/render/measure";
import { useManualFrames, setFrameDriver } from "../../src/animation/frame";

test "measurement uses the host after the current mount and layout work" {
	const frames = useManualFrames();
	const host = mockHost();
	const node = mockNode("view") as unknown as HostNode;
	let width = 10.0;
	host.measureInWindow = (n: HostNode): Result<MeasureRect, MeasureError> => Result.ok({ x: 12, y: 30, width, height: 20 });
	const handle = new ElementHandle(host, node, (): boolean => true);
	let calls: int32 = 0;
	handle.measureInWindow((rect: MeasureRect): void => {
		calls += 1;
		assert rect.x === 12 && rect.y === 30 && rect.width === 40 && rect.height === 20;
	});
	width = 40;
	assert calls === 0;
	frames.step(1);
	assert calls === 1;
	setFrameDriver(null);
}

test "measurement rejects invalid ancestry and cross-host handles without fabricated bounds" {
	const frames = useManualFrames();
	const host = mockHost();
	const node = mockNode("view") as unknown as HostNode;
	host.measureLayout = (n: HostNode, ancestor: HostNode): Result<MeasureRect, MeasureError> => Result.err(MeasureError.NotAncestor);
	const handle = new ElementHandle(host, node, (): boolean => true);
	const ancestor = new ElementHandle(host, mockNode("other") as unknown as HostNode, (): boolean => true);
	let failed = false;
	handle.measureLayout(ancestor, (rect: MeasureRect): void => { assert false; }, (error: MeasureError): void => {
		failed = error === MeasureError.NotAncestor;
	});
	frames.step(1);
	assert failed;
	let crossHost = false;
	try {
		handle.measureLayout(new ElementHandle(mockHost(), node, (): boolean => true), (rect: MeasureRect): void => {});
	} catch { crossHost = true; }
	assert crossHost;
	setFrameDriver(null);
}

test "queued measurement does not call an unmounted owner" {
	const frames = useManualFrames();
	const host = mockHost();
	let mounted = true;
	let queried = false;
	host.measureInWindow = (n: HostNode): Result<MeasureRect, MeasureError> => {
		queried = true;
		return Result.ok({ x: 0, y: 0, width: 10, height: 10 });
	};
	const handle = new ElementHandle(host, mockNode("view") as unknown as HostNode, (): boolean => mounted);
	handle.measureInWindow((rect: MeasureRect): void => { assert false; });
	mounted = false;
	frames.step(1);
	assert !queried;
	let rejected = false;
	try { handle.measureInWindow((rect: MeasureRect): void => {}); } catch { rejected = true; }
	assert rejected;
	setFrameDriver(null);
}

test "measurement drops success when the host query unmounts the target" {
	const frames = useManualFrames();
	const host = mockHost();
	let mounted = true;
	host.measureInWindow = (node: HostNode): Result<MeasureRect, MeasureError> => {
		mounted = false;
		return Result.ok({ x: 0, y: 0, width: 10, height: 10 });
	};
	const handle = new ElementHandle(host, mockNode("view") as unknown as HostNode, (): boolean => mounted);
	let delivered = false;
	handle.measureInWindow((rect: MeasureRect): void => { delivered = true; });
	frames.step(1);
	setFrameDriver(null);
	assert !delivered;
}

test "measurement drops failure when the host query unmounts the ancestor" {
	const frames = useManualFrames();
	const host = mockHost();
	let mounted = true;
	host.measureLayout = (node: HostNode, parent: HostNode): Result<MeasureRect, MeasureError> => {
		mounted = false;
		return Result.err(MeasureError.NotMounted);
	};
	const handle = new ElementHandle(host, mockNode("view") as unknown as HostNode, (): boolean => true);
	const parent = new ElementHandle(host, mockNode("parent") as unknown as HostNode, (): boolean => mounted);
	let delivered = false;
	handle.measureLayout(parent, (rect: MeasureRect): void => { delivered = true; }, (error: MeasureError): void => { delivered = true; });
	frames.step(1);
	setFrameDriver(null);
	assert !delivered;
}

test "unsupported measurement reports an explicit failure" {
	const frames = useManualFrames();
	const handle = new ElementHandle(mockHost(), mockNode("view") as unknown as HostNode, (): boolean => true);
	let failed = false;
	handle.measureInWindow((rect: MeasureRect): void => { assert false; }, (error: MeasureError): void => { failed = error === MeasureError.Unsupported; });
	frames.step(1);
	assert failed;
	setFrameDriver(null);
}
