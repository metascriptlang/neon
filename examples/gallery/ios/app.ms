@compile("../../ios/entry.m", "-fobjc-arc");

import { GalleryApp } from "../../components/gallery";
import { runApp } from "../../../src/platform/native/host";

runApp(GalleryApp);
