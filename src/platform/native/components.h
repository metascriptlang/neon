#ifndef NEON_NATIVE_COMPONENTS_H
#define NEON_NATIVE_COMPONENTS_H

void *niSwitchCreate(void);
void *niIndicatorCreate(void);
// A layer above the app for a Modal: blocks touches below it, takes the
// platform's back/escape as control phase 7 (request close).
void *niModalCreate(void);
// RN's InputAccessoryView (iOS only): the views added to it become the keyboard's accessory
// view for a TextInput whose `inputAccessoryViewID` equals its `nativeID` prop; with no
// `nativeID` it is the accessory of its own first responder status.
void *niInputAccessoryViewCreate(void);
// The media views take a `command` prop ("name\x1fargument") for their imperative methods.
void *niWebViewCreate(void);
void *niVideoCreate(void);
void *niCameraCreate(void);
// An <Svg>: draws its `displayList` prop, grammar in src/components/svg/scene.ms encodeScene,
// sized by layout only.
void *niSvgCreate(void);

#endif
