// Neon's public surface. Platform hosts stay out on purpose — a program picks
// exactly one and pays for exactly one.

export { Signal, createSignal, untrack, batch } from "./core/signal";
export { createEffect } from "./core/effect";
export { createMemo } from "./core/memo";
export { createRoot, runWithOwner } from "./core/owner";
export { getOwner } from "./core/runtime";
export { onCleanup } from "./core/cleanup";
export { mapArray, indexArray } from "./core/array";
export { Dispose } from "./core/types";

export { NeonNode, renderToString } from "./render/node";
export { Host, HostNode } from "./render/hostTypes";
export { NeonView, mountView, viewOf, renderNode, renderToHost } from "./render/host";
export { createComponent } from "./render/component";
export { Context, ProviderProps, createContext, useContext } from "./render/context";
export { NeonEvent, neonEvent } from "./render/event";
export { reconcileArrays } from "./render/reconcile";

export {
	Style, StyleValue, FlexDirection, Justify, Align, PositionType, Wrap, Display,
	TextAlign, FontWeight, emptyStyle, mergeStyle, layerStyles,
} from "./render/style";
export { styleToCss } from "./render/css";
export { onCssChange, registerCss, collectCss, mountSheet, cssRuleCount, resetCss } from "./render/sheet";

export { element } from "./macros/ui/element";
export { direct } from "./macros/ui/direct";
export { createStyles, styleOf } from "./macros/ui/style";
export { createTheme, setTheme, themeOf, setThemeCss } from "./macros/ui/theme";
export { For, Index, Show } from "./macros/ui/flow";

export { View, Text, Pressable, TextInput } from "./components/primitives";
