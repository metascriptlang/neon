@compile("../../ios/entry.m", "-fobjc-arc");

import { BigList } from "../../components/bigList";
import { runApp } from "../../../src/platform/native/host";

runApp(BigList);
