import { element } from "../../src/macros/ui/element";
import { NeonNode } from "../../src/render/node";
import { Scene3D, PointLight } from "../../src/components/scene3d";

export const lamp: NeonNode = element(<Scene3D><PointLight castShadow={true} /></Scene3D>);
