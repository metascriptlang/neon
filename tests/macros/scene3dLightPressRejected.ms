import { element } from "../../src/macros/ui/element";
import { NeonNode } from "../../src/render/node";
import { Light } from "../../src/components/scene3d";
import { Pointer3DEvent } from "../../src/components/scene3d";
import { LightKind } from "../../../void/src/void3d/scene";

export const lamp: NeonNode = element(<Light kind={LightKind.Point} onPress={(e: Pointer3DEvent): void => {}} />);
