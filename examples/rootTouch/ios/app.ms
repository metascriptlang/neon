@compile("../../ios/entry.m", "-fobjc-arc");
@compile("./rootTouchHarness.m", "-fobjc-arc");

import { RootTouchFixture } from "../../components/rootTouch";
import { runApp } from "../../../src/platform/native/host";

runApp(RootTouchFixture);
