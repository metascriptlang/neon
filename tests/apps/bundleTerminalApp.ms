import { element } from "../../src/macros/ui/element";
import { render } from "../../src/render/host";
import { HostNode } from "../../src/render/hostTypes";
import { terminalHost } from "../../src/platform/terminal/host";
import { paintTree } from "../../src/platform/terminal/paint";
import { createTerminalNode } from "../../src/platform/terminal/types";
import { View, Text } from "../../src/components/primitives";

const root = createTerminalNode("box");
render(element(<View><Text>hi</Text></View>), terminalHost(), root as unknown as HostNode);
console.log(paintTree(root, 80).join("\n"));
