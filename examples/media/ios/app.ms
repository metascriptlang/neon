@compile("../../ios/entry.m", "-fobjc-arc");

import { MediaApp } from "../media";
import { runApp } from "../../../src/platform/native/host";

runApp(MediaApp);
