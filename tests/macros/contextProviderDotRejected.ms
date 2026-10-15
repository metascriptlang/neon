import { element } from "../../src/macros/ui/element";
import { NeonNode } from "../../src/render/node";
import { View } from "../../src/components/primitives";
import { createContext } from "../../src/render/context";

const Tone = createContext<string>("plain");

export const tone: NeonNode = element(<Tone.Provider value="dark"><View /></Tone.Provider>);
