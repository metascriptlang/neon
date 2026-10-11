@compile("../../ios/entry.m", "-fobjc-arc");

import { NavigationDemo } from "../../components/navigation";
import { runApp } from "../../../src/platform/native/host";

runApp(NavigationDemo);
