// Neon's public surface. Platform hosts stay out on purpose — a program picks
// exactly one and pays for exactly one.

export { Signal, createSignal, untrack, batch, accessor, valueOf, Accessor, Setter } from "./core/signal";
export { createEffect } from "./core/effect";
export { createMemo } from "./core/memo";
export { createSelector } from "./core/selector";
export { createRoot, runWithOwner } from "./core/owner";
export { getOwner } from "./core/runtime";
export { onCleanup } from "./core/cleanup";
export { catchError } from "./core/error";
export { mapArray, indexArray } from "./core/array";
export { createList, List, ListOp, ListQueue } from "./core/list";
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
export { For, ForList, Index, Show } from "./macros/ui/flow";

export { View, Text, Pressable, TextInput, ScrollView, ScrollViewHandle, KeyboardDismissMode, KeyboardShouldPersistTaps, TextSelection } from "./components/primitives";
export {
	FlatList, FlatListHandle, ListRenderItemInfo, ItemLayout, EndReachedInfo, StartReachedInfo,
	ScrollToIndexFailedInfo, ScrollToIndexOptions, ScrollToItemOptions, ScrollToOffsetOptions, ScrollToEndOptions,
	ViewabilityConfig, ViewabilityConfigCallbackPair, ViewabilityInfo, ViewToken,
} from "./components/flatList";
export { VirtualizedList } from "./components/virtualizedList";
export {
	SectionBase, SectionInfo, SectionList, SectionListHandle, SectionListRenderItemInfo,
	SectionViewToken, SectionViewabilityInfo, ScrollToLocationParams, VirtualizedSectionList,
} from "./components/sectionList";

export { EventSubscription } from "./api/subscription";
export { AppServices, AlertRequest, AlertButtonSpec, ShareRequest, installAppServices } from "./api/services";
export { Platform, PlatformOSType } from "./api/platform";
export { Dimensions, DimensionsChange, DimensionsKey, ScaledSize } from "./api/dimensions";
export { PixelRatio } from "./api/pixelRatio";
export { StyleSheet } from "./api/styleSheet";
export { Appearance, AppearancePreferences } from "./api/appearance";
export { Keyboard, KeyboardEvent, KeyboardEventCoordinates, KeyboardEventName } from "./api/keyboard";
export { AppState, AppStateEvent, AppStateStatus, useAppState } from "./api/appState";
export { BackHandler } from "./api/backHandler";
export { Alert, AlertButton, AlertButtonStyle, AlertOptions } from "./api/alert";
export { Linking, LinkingUrlEvent } from "./api/linking";
export { Share, ShareAction, ShareContent, ShareOptions } from "./api/share";
export { Vibration } from "./api/vibration";
export { Clipboard } from "./api/clipboard";
export { AccessibilityInfo, AccessibilityChangeEventName, useScreenReaderEnabled } from "./api/accessibilityInfo";
export { AsyncStorage, AsyncStorageHook, KeyValuePair, StringPair, useAsyncStorage } from "./api/asyncStorage";
export {
	NetInfo, NetInfoChangeHandler, NetInfoDetails, NetInfoState, NetInfoStateType, NetInfoUnsubscribe, useNetInfo,
} from "./api/netInfo";
export {
	AndroidPermissionNames, AndroidPermissionResults, PermissionName, PermissionResponse, Permissions, PermissionsAndroid,
	PermissionsAndroidResult, PermissionStatus, Rationale,
} from "./api/permissions";
export {
	Geolocation, GeolocationConfiguration, GeolocationCoordinates, GeolocationError, GeolocationFailure, GeolocationOptions,
	GeolocationResponse, GeolocationSuccess, Location, LocationAccuracy, LocationObject, LocationObjectCoords,
	LocationOptions, LocationSubscription,
} from "./api/geolocation";
export { Haptics, ImpactFeedbackStyle, NotificationFeedbackType } from "./api/haptics";
export { DeviceInfo, DeviceType } from "./api/deviceInfo";
export {
	Calendar, Locale, LocalizeLocale, NumberFormatSettings, getCalendars, getCountry, getCurrencies, getLocales,
	getLocalizeLocales, getNumberFormatSettings, getTemperatureUnit, getTimeZone, uses24HourClock, usesMetricSystem,
} from "./api/localization";
export {
	DEFAULT_ACTION_IDENTIFIER, Notification, NotificationBehavior, NotificationContent, NotificationContentInput,
	NotificationHandler, NotificationRequest, NotificationRequestInput, NotificationResponse, NotificationTriggerInput,
	Notifications,
} from "./api/notifications";
export {
	Animated, CompositeAnimation, useAnimatedValue, AnimatedNode, AnimatedValue, AnimatedValueXY,
	AnimatedInterpolation, AnimatedStringInterpolation, Easing, EasingFunction, LayoutAnimation,
	LayoutAnimationPresets, Presence, EndResult,
} from "./animation/index";

export * from "./navigation/index";
