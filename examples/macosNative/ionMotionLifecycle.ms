// A handed track survives a resize and the view leaving and re-entering its window.
//   msc build examples/macosNative/ionMotionLifecycle.ms --output=out/macosIonMotionLifecycle
//   out/macosIonMotionLifecycle    resizes a turning view and detaches a forever-drifting one mid-animation,
//                                  and exits with the failure count (examples/layerMotion/lifecycle.ms)

import { runNativeWindow, nativeWindowOptions } from "../../src/platform/macos/ion";
import { MotionLifecycle } from "../layerMotion/lifecycle";
import { exit } from "std/process";

const options = nativeWindowOptions("Neon motion lifecycle on Core Animation", 480, 300);
options.topmost = true;
exit(runNativeWindow(options, MotionLifecycle, null));
