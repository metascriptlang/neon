@compile("../../ios/entry.m", "-fobjc-arc");

import { CaptureApp } from "../capture";
import { runApp } from "../../../src/platform/native/host";

runApp(CaptureApp);
