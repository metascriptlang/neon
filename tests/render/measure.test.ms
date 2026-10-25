import { Host, HostNode, mockHost } from "../../src/render/host";
import { MeasureRect, MeasureError } from "../../src/render/hostTypes";
import { ElementHandle, DOMRect } from "../../src/render/measure";

function rectText(r: DOMRect): string {
	return `${r.x},${r.y},${r.width},${r.height} t${r.top} r${r.right} b${r.bottom} l${r.left}`;
}

function nested(host: Host): HostNode[] {
	const outer = host.createElement("view");
	const inner = host.createElement("view");
	const beside = host.createElement("view");
	host.append(outer, inner);
	host.append(outer, beside);
	return [outer, inner, beside];
}

test "measure answers the layout origin in the parent beside the window frame, before the call returns" {
	const host = mockHost();
	const [outer, inner] = nested(host);
	host.measureInWindow = (n: HostNode): Result<MeasureRect, MeasureError> => Result.ok({ x: 30, y: 60, width: 100, height: 80 });
	host.measureLayout = (n: HostNode, ancestor: HostNode): Result<MeasureRect, MeasureError> => {
		assert n === inner && ancestor === outer;
		return Result.ok({ x: 10, y: 20, width: 50, height: 40 });
	};
	const handle = new ElementHandle(host, inner, (): boolean => true);
	let log = "";
	handle.measure((x: number, y: number, width: number, height: number, pageX: number, pageY: number): void => {
		log += `measure ${x},${y},${width},${height},${pageX},${pageY};`;
	});
	log += "after;";
	handle.measureInWindow((x: number, y: number, width: number, height: number): void => {
		log += `window ${x},${y},${width},${height};`;
	});
	log += "after;";
	assert log === "measure 10,20,100,80,30,60;after;window 30,60,100,80;after;", log;
	assert rectText(handle.getBoundingClientRect()) === "30,60,100,80 t60 r130 b140 l30", rectText(handle.getBoundingClientRect());
}

test "a node with no parent measures its window origin as its layout origin" {
	const host = mockHost();
	host.measureInWindow = (n: HostNode): Result<MeasureRect, MeasureError> => Result.ok({ x: 3, y: 4, width: 5, height: 6 });
	const handle = new ElementHandle(host, host.createElement("view"), (): boolean => true);
	let got = "";
	handle.measure((x: number, y: number, width: number, height: number, pageX: number, pageY: number): void => {
		got = `${x},${y},${width},${height},${pageX},${pageY}`;
	});
	assert got === "3,4,5,6,3,4", got;
}

test "measureLayout answers the host's layout frame, and calls onFail for a node that is not its ancestor or another host's" {
	const host = mockHost();
	const [outer, inner, beside] = nested(host);
	host.measureLayout = (n: HostNode, ancestor: HostNode): Result<MeasureRect, MeasureError> =>
		ancestor === outer ? Result.ok({ x: 5, y: 10, width: 50, height: 40 }) : Result.err(MeasureError.NotAncestor);
	const handle = new ElementHandle(host, inner, (): boolean => true);
	let log = "";
	const success = (left: number, top: number, width: number, height: number): void => { log += `layout ${left},${top},${width},${height};`; };
	const fail = (): void => { log += "onFail;"; };
	handle.measureLayout(new ElementHandle(host, outer, (): boolean => true), success, fail);
	handle.measureLayout(new ElementHandle(host, beside, (): boolean => true), success, fail);
	handle.measureLayout(new ElementHandle(host, beside, (): boolean => true), success);
	handle.measureLayout(new ElementHandle(mockHost(), outer, (): boolean => true), success, fail);
	assert log === "layout 5,10,50,40;onFail;onFail;", log;
}

test "an unmounted node, a node not laid out and a host that cannot measure answer zeros and never throw" {
	const cases: string[] = ["unmounted", "not laid out", "unsupported"];
	for (const name of cases) {
		const host = mockHost();
		const [outer, inner] = nested(host);
		if (name !== "unsupported") {
			host.measureInWindow = (n: HostNode): Result<MeasureRect, MeasureError> =>
				name === "not laid out" ? Result.err(MeasureError.NotLaidOut) : Result.ok({ x: 1, y: 2, width: 3, height: 4 });
			host.measureLayout = (n: HostNode, ancestor: HostNode): Result<MeasureRect, MeasureError> =>
				name === "not laid out" ? Result.err(MeasureError.NotLaidOut) : Result.ok({ x: 1, y: 2, width: 3, height: 4 });
		}
		const mounted = name !== "unmounted";
		const handle = new ElementHandle(host, inner, (): boolean => mounted);
		let log = "";
		handle.measure((x: number, y: number, width: number, height: number, pageX: number, pageY: number): void => {
			log += `${x}${y}${width}${height}${pageX}${pageY};`;
		});
		handle.measureInWindow((x: number, y: number, width: number, height: number): void => { log += `${x}${y}${width}${height};`; });
		handle.measureLayout(new ElementHandle(host, outer, (): boolean => true),
			(left: number, top: number, width: number, height: number): void => { log += "measured;"; }, (): void => { log += "onFail;"; });
		handle.measureLayout(new ElementHandle(host, outer, (): boolean => true),
			(left: number, top: number, width: number, height: number): void => { log += "measured;"; });
		log += rectText(handle.getBoundingClientRect());
		assert log === "000000;0000;onFail;0,0,0,0 t0 r0 b0 l0", name + ": " + log;
	}
}
