@compile("../../ios/entry.m", "-fobjc-arc");

import { SvgGallery } from "../../components/svgGallery";
import { runApp } from "../../../src/platform/native/host";

runApp(SvgGallery);
