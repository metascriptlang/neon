import { element } from "../../src/macros/ui/element";
import { NeonNode } from "../../src/render/node";
import { Text, TextInputHandle } from "../../src/components/primitives";

export const label: NeonNode = element(<Text ref={(h: TextInputHandle): void => { h.clear(); }}>a</Text>);
