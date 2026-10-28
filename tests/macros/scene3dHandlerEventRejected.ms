import { element } from "../../src/macros/ui/element";
import { NeonNode } from "../../src/render/node";
import { Mesh } from "../../src/components/scene3d";
import { MeshId, NO_MESH } from "../../../void/src/void3d/draw";

function wrong(e: string): void {}

export const box: NeonNode = element(<Mesh mesh={NO_MESH} onPress={wrong} />);
