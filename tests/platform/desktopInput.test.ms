import { DesktopInput, DesktopPointer } from "../../src/platform/native/desktopInput";
import { useManualFrames, setFrameDriver, framePending } from "../../src/animation/frame";

function pointer(kind: "motion" | "wheel", x: float32, delta: float32): DesktopPointer {
	return { kind, x, y: 0.0, dx: 0.0, dy: delta };
}

test "desktop motion keeps the latest sample and wheel preserves the summed distance" {
	const clock = useManualFrames();
	const seen: string[] = [];
	const input = new DesktopInput((e: DesktopPointer): void => {
		seen.push(`${e.kind} ${e.x} ${e.dy}`);
	});
	input.push(pointer("motion", 10.0, 0.0));
	input.push(pointer("motion", 20.0, 0.0));
	input.push(pointer("wheel", 20.0, 2.0));
	input.push(pointer("wheel", 30.0, 3.0));
	input.push(pointer("motion", 40.0, 0.0));
	assert seen.length === 0;
	clock.advance(16);
	assert seen.join(",") === "motion 20 0,wheel 30 5,motion 40 0", seen.join(",");
	assert clock.frames === 1 && !framePending();
	setFrameDriver(null);
}

test "a discrete boundary drains desktop input before it changes geometry or focus" {
	const clock = useManualFrames();
	const seen: string[] = [];
	const input = new DesktopInput((e: DesktopPointer): void => {
		seen.push(`${e.kind} ${e.x}`);
	});
	input.push(pointer("motion", 10.0, 0.0));
	input.push(pointer("wheel", 10.0, 2.0));
	input.drain();
	seen.push("resize");
	clock.advance(16);
	assert seen.join(",") === "motion 10,wheel 10,resize", seen.join(",");
	assert !framePending();
	input.push(pointer("motion", 20.0, 0.0));
	input.stop();
	clock.advance(16);
	assert seen.length === 3 && !framePending();
	setFrameDriver(null);
}

test "input queued by a desktop input handler belongs to the next frame" {
	const clock = useManualFrames();
	const seen: float32[] = [];
	let again: DesktopInput | null = null;
	const input = new DesktopInput((e: DesktopPointer): void => {
		seen.push(e.x);
		if (e.x === 10.0) {
			(again as DesktopInput).push(pointer("motion", 20.0, 0.0));
		}
	});
	again = input;
	input.push(pointer("motion", 10.0, 0.0));
	clock.advance(16);
	assert seen.join(",") === "10" && framePending();
	clock.advance(16);
	assert seen.join(",") === "10,20" && !framePending();
	setFrameDriver(null);
}
