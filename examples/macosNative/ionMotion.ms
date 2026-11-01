// A track handed to Core Animation keeps moving while the main thread is blocked on purpose.
//   msc build examples/macosNative/ionMotion.ms --output=out/macosIonMotion
//   out/macosIonMotion    blocks the main thread for 300 ms mid-animation and exits 0 when the
//                         presentation layer, sampled on a background thread, advanced by the
//                         blocked time while the player did not (examples/layerMotion/check.ms)

import { runNativeWindow, nativeWindowOptions } from "../../src/platform/macos/ion";
import { MotionCheck } from "../layerMotion/check";
import { exit } from "std/process";

const options = nativeWindowOptions("Neon motion on Core Animation", 480, 200);
options.topmost = true;
exit(runNativeWindow(options, MotionCheck, null));
