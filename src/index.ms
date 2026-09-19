// Neon's public surface. Platform hosts stay out on purpose — a program picks
// exactly one and pays for exactly one.

export { Signal, createSignal, untrack, batch, accessor, valueOf, Accessor, Setter } from "./core/signal";
export { createEffect } from "./core/effect";
export { createMemo } from "./core/memo";
export { createRoot, runWithOwner } from "./core/owner";
export { getOwner } from "./core/runtime";
export { onCleanup } from "./core/cleanup";
export { mapArray, indexArray } from "./core/array";
export { Dispose } from "./core/types";

export { Host, HostNode, NeonNode } from "./render/hostTypes";
export { render } from "./render/host";
export { renderToString } from "./render/ssr";
export { createComponent } from "./render/component";
export { Context, ProviderProps, createContext, useContext } from "./render/context";
export { NeonEvent, neonEvent } from "./render/event";
export { Row, makeRow, rowOf, place, mountAt, moveRow, removeRow, reconcileArrays } from "./render/reconcile";

export {
	Style, StyleValue, FlexDirection, Justify, Align, PositionType, Wrap, Display,
	TextAlign, FontWeight, emptyStyle, mergeStyle, layerStyles,
} from "./render/style";
export { styleToCss } from "./render/css";
export { onCssChange, registerCss, collectCss, mountSheet, cssRuleCount, resetCss } from "./render/sheet";

export { element } from "./macros/ui/element";
export { createStyles, styleOf } from "./macros/ui/style";
export { createTheme, setTheme, themeOf, setThemeCss } from "./macros/ui/theme";
export { For, Index, Show } from "./macros/ui/flow";

export { View, Text, Pressable, TextInput } from "./components/primitives";
