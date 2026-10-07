@compile("../../ios/entry.m", "-fobjc-arc");

import { ApiDemo } from "../../components/apis";
import { runApp } from "../../../src/platform/native/host";

runApp(ApiDemo);
