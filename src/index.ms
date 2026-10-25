// Neon's public surface. Platform hosts stay out on purpose — a program picks
// exactly one and pays for exactly one.

export { Signal, createSignal, untrack, accessor, valueOf, Accessor, Setter } from "./core/signal";
export { createEffect, createRenderEffect, onSettled, EffectOptions, EffectBundle } from "./core/effect";
export { createMemo, refresh } from "./core/memo";
export { createRoot, runWithOwner, createUniqueId } from "./core/owner";
export { getOwner, flush, isPending, latest, resetErrorHalt } from "./core/runtime";
export { onCleanup } from "./core/cleanup";
export { createErrorBoundary, createLoadingBoundary } from "./core/boundary";
export { mapArray, mapArrayKeyedBy, mapArrayByPosition, repeat } from "./core/array";
export { createList, List, ListOp, ListQueue } from "./core/list";
export { Dispose, Cleanup, NotReadyError } from "./core/types";
export { createStore, createProjection, snapshot, reconcile, Store, Draft, SetStoreFunction } from "./core/store";

export { Host, HostNode, NeonNode } from "./render/hostTypes";
export { ElementHandle, ElementRef, DOMRect, MeasureRect, MeasureError } from "./render/measure";
export { render } from "./render/host";
export { hydrate } from "./render/hydrate";
export { renderToString, renderToMarkup, renderToStream, StreamSink, SsrMarkup } from "./render/ssr";
export { App, DocumentProps, RequestEvent, RequestHeaders, Served, ServedRequest, getRequestEvent, htmlDocument, serve } from "./render/serve";
export { isServer } from "./render/environment";
export { Head } from "./render/head";
export { createComponent } from "./render/component";
export { Context, ContextNotFoundError, NoOwnerError, createContext, useContext } from "./render/context";
export { NeonEvent, neonEvent, stopPropagation } from "./render/event";
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
export { For, ForKeyedBy, ForUnkeyed, Repeat, ForList, Show, ShowKeyed, ShowWith, ShowKeyedWith, Match, Case, CaseKeyed, CaseWith, CaseKeyedWith, Errored, Loading } from "./macros/ui/flow";

export { View, Text, Pressable, TextInput, ScrollView, ScrollViewHandle, KeyboardDismissMode, KeyboardShouldPersistTaps, TextSelection } from "./components/primitives";
export {
	FlatList, FlatListHandle, ListRenderItemInfo, ItemLayout, EndReachedInfo, StartReachedInfo,
	ScrollToIndexFailedInfo, ScrollToIndexOptions, ScrollToItemOptions, ScrollToOffsetOptions, ScrollToEndOptions,
	ViewabilityConfig, ViewabilityConfigCallbackPair, ViewabilityInfo, ViewToken,
} from "./components/flatList";
export { TextInputHandle } from "./components/primitives";
export { Image, ImageProps, ImageSource, ImageResizeMode, ImageLoader } from "./components/image";
export { Modal, ModalAnimationType } from "./components/modal";
export { SafeAreaView } from "./components/safeAreaView";
export { KeyboardAvoidingView, KeyboardAvoidingBehavior } from "./components/keyboardAvoidingView";
export { RefreshControl } from "./components/refreshControl";
export { Switch } from "./components/switch";
export { ActivityIndicator, IndicatorSize } from "./components/activityIndicator";
export { Portal } from "./render/portal";
export {
	TouchableOpacity,
	TouchableHighlight,
	TouchableWithoutFeedback,
} from "./components/touchable";
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
when (js) {
	export { ScrollPosition, useWindowScrollPosition, useWindowScrollRange } from "./api/pageScroll";
}
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
export { lazy } from "./macros/lazy";
export { lazyModule, preloadLazy, preloadServedLazy } from "./render/lazy";
