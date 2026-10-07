@compile("../../ios/entry.m", "-fobjc-arc");

import { ScrollMatrix } from "../../components/scrollMatrix";
import { runApp } from "../../../src/platform/native/host";

runApp(ScrollMatrix);
