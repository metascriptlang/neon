#include "runtime/promise/dispatch.h"
#include "../native/bridge.h"
#include "../native/loop.h"
#include <android/log.h>
#include <android/looper.h>
#include <jni.h>
#include <math.h>
#include <stdlib.h>
#include <sys/timerfd.h>
#include <unistd.h>

extern void MsMain(void);

static JavaVM *g_vm;
static int g_started;
static msClosure s_mount;
static msClosure s_touch;
static msClosure s_resize;
static msClosure s_teardown;
static msClosure s_scroll;
static msClosure s_loop;
static int g_lastTag;
static int g_lastPhase;
static int g_scrollTag;
static float g_scrollX, g_scrollY, g_scrollW, g_scrollH, g_scrollContentW, g_scrollContentH;
static int g_scrollPhase;

static jobject g_root;
static jobject g_container;
static jobject g_context;
static float g_density = 1;
static float g_width;
static float g_height;
static float g_measuredW;
static float g_measuredH;
static int g_loopFd = -1;

static struct {
	jclass view, viewGroup, frameLayout, layoutParams, textView, gradientDrawable, integer, touch;
	jclass scroll;
	jmethodID scrollInit, scrollSetTag, scrollSetOption, scrollSetContentSize, scrollTo, scrollAddContent, scrollDispose, viewSetClickable;
	jmethodID viewGetParent, viewSetLayoutParams, viewSetAlpha, viewGetBackground, viewSetBackground;
	jmethodID viewMeasure, viewGetMeasuredWidth, viewGetMeasuredHeight, viewSetTag, viewGetRootWindowInsets;
	jmethodID viewSetOnTouchListener, touchInit;
	jmethodID viewGetContext, groupAddView, groupRemoveView, frameInit, paramsInit;
	jfieldID paramsLeft, paramsTop;
	jmethodID textInit, textSetText, textSetTextColor, textSetTextSize, textSetTypeface;
	jmethodID drawableInit, drawableSetColor, drawableSetCornerRadius, integerValueOf;
	jobject typefaceDefault, typefaceBold;
	int sdk;
} J;

static void loopArm(int ms) {
	if (g_loopFd < 0) return;
	struct itimerspec at = {0};
	if (ms >= 0) {
		at.it_value.tv_sec = ms / 1000;
		at.it_value.tv_nsec = (long)(ms % 1000) * 1000000L + 1;
	}
	timerfd_settime(g_loopFd, 0, &at, NULL);
}

static void invoke(msClosure c) {
	if (c.env) ((void (*)(void *))c.fn)(c.env);
	else ((void (*)(void))c.fn)();
}

static int loopPump(int fd, int events, void *data) {
	(void)events;
	(void)data;
	uint64_t expirations;
	(void)read(fd, &expirations, sizeof expirations);
	if (s_loop.fn) invoke(s_loop);
	else niLoopRun();
	loopArm(niLoopNext());
	return 1;
}

static void loopStart(void) {
	(void)msGetDispatcher();
	g_loopFd = timerfd_create(CLOCK_MONOTONIC, TFD_NONBLOCK | TFD_CLOEXEC);
	ALooper_addFd(ALooper_forThread(), g_loopFd, ALOOPER_POLL_CALLBACK, ALOOPER_EVENT_INPUT, loopPump, NULL);
}

static void call0(msClosure c) {
	if (!c.fn) return;
	invoke(c);
	loopArm(0);
}

static JNIEnv *env(void) {
	JNIEnv *e = NULL;
	if (!g_vm || (*g_vm)->GetEnv(g_vm, (void **)&e, JNI_VERSION_1_6) != JNI_OK || !e) {
		__android_log_print(ANDROID_LOG_FATAL, "Neon", "bridge called off a JNI thread");
		abort();
	}
	return e;
}

static void check(JNIEnv *e, const char *op) {
	if (!(*e)->ExceptionCheck(e)) return;
	(*e)->ExceptionDescribe(e);
	__android_log_print(ANDROID_LOG_FATAL, "Neon", "%s threw", op);
	abort();
}

static jclass globalClass(JNIEnv *e, const char *name) {
	jclass local = (*e)->FindClass(e, name);
	check(e, name);
	jclass global = (*e)->NewGlobalRef(e, local);
	(*e)->DeleteLocalRef(e, local);
	return global;
}

static jmethodID method(JNIEnv *e, jclass c, const char *name, const char *sig) {
	jmethodID id = (*e)->GetMethodID(e, c, name, sig);
	check(e, name);
	return id;
}

static jobject staticObject(JNIEnv *e, const char *cls, const char *name, const char *sig) {
	jclass c = (*e)->FindClass(e, cls);
	check(e, cls);
	jobject local = (*e)->GetStaticObjectField(e, c, (*e)->GetStaticFieldID(e, c, name, sig));
	check(e, name);
	jobject global = (*e)->NewGlobalRef(e, local);
	(*e)->DeleteLocalRef(e, local);
	(*e)->DeleteLocalRef(e, c);
	return global;
}

static void cacheJni(JNIEnv *e) {
	J.view = globalClass(e, "android/view/View");
	J.viewGroup = globalClass(e, "android/view/ViewGroup");
	J.frameLayout = globalClass(e, "android/widget/FrameLayout");
	J.layoutParams = globalClass(e, "android/widget/FrameLayout$LayoutParams");
	J.textView = globalClass(e, "android/widget/TextView");
	J.gradientDrawable = globalClass(e, "android/graphics/drawable/GradientDrawable");
	J.integer = globalClass(e, "java/lang/Integer");
	J.touch = globalClass(e, "dev/metascript/neon/Touch");
	J.scroll = globalClass(e, "dev/metascript/neon/Scroll");
	J.scrollInit = method(e, J.scroll, "<init>", "(Landroid/content/Context;)V");
	J.scrollSetTag = method(e, J.scroll, "setNeonTag", "(I)V");
	J.scrollSetOption = method(e, J.scroll, "setOption", "(Ljava/lang/String;Ljava/lang/String;)V");
	J.scrollSetContentSize = method(e, J.scroll, "setContentSize", "(II)V");
	J.scrollTo = method(e, J.scroll, "neonScrollTo", "(IIZ)V");
	J.scrollAddContent = method(e, J.scroll, "addContent", "(Landroid/view/View;)V");
	J.scrollDispose = method(e, J.scroll, "dispose", "()V");
	J.viewSetClickable = method(e, J.view, "setClickable", "(Z)V");

	J.viewGetParent = method(e, J.view, "getParent", "()Landroid/view/ViewParent;");
	J.viewSetLayoutParams = method(e, J.view, "setLayoutParams", "(Landroid/view/ViewGroup$LayoutParams;)V");
	J.viewSetAlpha = method(e, J.view, "setAlpha", "(F)V");
	J.viewGetBackground = method(e, J.view, "getBackground", "()Landroid/graphics/drawable/Drawable;");
	J.viewSetBackground = method(e, J.view, "setBackground", "(Landroid/graphics/drawable/Drawable;)V");
	J.viewMeasure = method(e, J.view, "measure", "(II)V");
	J.viewGetMeasuredWidth = method(e, J.view, "getMeasuredWidth", "()I");
	J.viewGetMeasuredHeight = method(e, J.view, "getMeasuredHeight", "()I");
	J.viewSetTag = method(e, J.view, "setTag", "(Ljava/lang/Object;)V");
	J.viewGetRootWindowInsets = method(e, J.view, "getRootWindowInsets", "()Landroid/view/WindowInsets;");
	J.viewGetContext = method(e, J.view, "getContext", "()Landroid/content/Context;");
	J.viewSetOnTouchListener = method(e, J.view, "setOnTouchListener", "(Landroid/view/View$OnTouchListener;)V");
	J.touchInit = method(e, J.touch, "<init>", "(I)V");
	J.groupAddView = method(e, J.viewGroup, "addView", "(Landroid/view/View;)V");
	J.groupRemoveView = method(e, J.viewGroup, "removeView", "(Landroid/view/View;)V");
	J.frameInit = method(e, J.frameLayout, "<init>", "(Landroid/content/Context;)V");
	J.paramsInit = method(e, J.layoutParams, "<init>", "(II)V");
	J.paramsLeft = (*e)->GetFieldID(e, J.layoutParams, "leftMargin", "I");
	J.paramsTop = (*e)->GetFieldID(e, J.layoutParams, "topMargin", "I");
	check(e, "MarginLayoutParams fields");
	J.textInit = method(e, J.textView, "<init>", "(Landroid/content/Context;)V");
	J.textSetText = method(e, J.textView, "setText", "(Ljava/lang/CharSequence;)V");
	J.textSetTextColor = method(e, J.textView, "setTextColor", "(I)V");
	J.textSetTextSize = method(e, J.textView, "setTextSize", "(IF)V");
	J.textSetTypeface = method(e, J.textView, "setTypeface", "(Landroid/graphics/Typeface;)V");
	J.drawableInit = method(e, J.gradientDrawable, "<init>", "()V");
	J.drawableSetColor = method(e, J.gradientDrawable, "setColor", "(I)V");
	J.drawableSetCornerRadius = method(e, J.gradientDrawable, "setCornerRadius", "(F)V");
	J.integerValueOf = (*e)->GetStaticMethodID(e, J.integer, "valueOf", "(I)Ljava/lang/Integer;");
	check(e, "Integer.valueOf");
	J.typefaceDefault = staticObject(e, "android/graphics/Typeface", "DEFAULT", "Landroid/graphics/Typeface;");
	J.typefaceBold = staticObject(e, "android/graphics/Typeface", "DEFAULT_BOLD", "Landroid/graphics/Typeface;");

	jclass version = (*e)->FindClass(e, "android/os/Build$VERSION");
	check(e, "Build.VERSION");
	J.sdk = (*e)->GetStaticIntField(e, version, (*e)->GetStaticFieldID(e, version, "SDK_INT", "I"));
	check(e, "SDK_INT");
	(*e)->DeleteLocalRef(e, version);
}

static int px(float dp) {
	return (int)lroundf(dp * g_density);
}

static int argb(float r, float g, float b, float a) {
	return ((int)lroundf(a * 255) << 24) | ((int)lroundf(r * 255) << 16) | ((int)lroundf(g * 255) << 8) | (int)lroundf(b * 255);
}

static void detach(JNIEnv *e, jobject view) {
	jobject parent = (*e)->CallObjectMethod(e, view, J.viewGetParent);
	check(e, "getParent");
	if (parent) {
		(*e)->CallVoidMethod(e, parent, J.groupRemoveView, view);
		check(e, "removeView");
		(*e)->DeleteLocalRef(e, parent);
	}
}

static void place(JNIEnv *e, jobject view, int x, int y, int w, int h) {
	jobject params = (*e)->NewObject(e, J.layoutParams, J.paramsInit, w, h);
	check(e, "LayoutParams");
	(*e)->SetIntField(e, params, J.paramsLeft, x);
	(*e)->SetIntField(e, params, J.paramsTop, y);
	(*e)->CallVoidMethod(e, view, J.viewSetLayoutParams, params);
	check(e, "setLayoutParams");
	(*e)->DeleteLocalRef(e, params);
}

static jobject background(JNIEnv *e, jobject view) {
	jobject drawable = (*e)->CallObjectMethod(e, view, J.viewGetBackground);
	check(e, "getBackground");
	if (drawable && (*e)->IsInstanceOf(e, drawable, J.gradientDrawable)) return drawable;
	if (drawable) (*e)->DeleteLocalRef(e, drawable);
	drawable = (*e)->NewObject(e, J.gradientDrawable, J.drawableInit);
	check(e, "GradientDrawable");
	(*e)->CallVoidMethod(e, view, J.viewSetBackground, drawable);
	check(e, "setBackground");
	return drawable;
}

static void systemBarInsets(JNIEnv *e, int *left, int *top, int *right, int *bottom) {
	*left = *top = *right = *bottom = 0;
	jobject insets = (*e)->CallObjectMethod(e, g_root, J.viewGetRootWindowInsets);
	check(e, "getRootWindowInsets");
	if (!insets) return;
	jclass windowInsets = (*e)->GetObjectClass(e, insets);
	if (J.sdk >= 30) {
		jclass type = (*e)->FindClass(e, "android/view/WindowInsets$Type");
		check(e, "WindowInsets.Type");
		jint bars = (*e)->CallStaticIntMethod(e, type, (*e)->GetStaticMethodID(e, type, "systemBars", "()I"));
		jint cutout = (*e)->CallStaticIntMethod(e, type, (*e)->GetStaticMethodID(e, type, "displayCutout", "()I"));
		check(e, "WindowInsets.Type masks");
		jobject box = (*e)->CallObjectMethod(e, insets,
			(*e)->GetMethodID(e, windowInsets, "getInsets", "(I)Landroid/graphics/Insets;"), bars | cutout);
		check(e, "getInsets");
		jclass boxClass = (*e)->GetObjectClass(e, box);
		*left = (*e)->GetIntField(e, box, (*e)->GetFieldID(e, boxClass, "left", "I"));
		*top = (*e)->GetIntField(e, box, (*e)->GetFieldID(e, boxClass, "top", "I"));
		*right = (*e)->GetIntField(e, box, (*e)->GetFieldID(e, boxClass, "right", "I"));
		*bottom = (*e)->GetIntField(e, box, (*e)->GetFieldID(e, boxClass, "bottom", "I"));
		check(e, "Insets fields");
	} else {
		*left = (*e)->CallIntMethod(e, insets, (*e)->GetMethodID(e, windowInsets, "getSystemWindowInsetLeft", "()I"));
		*top = (*e)->CallIntMethod(e, insets, (*e)->GetMethodID(e, windowInsets, "getSystemWindowInsetTop", "()I"));
		*right = (*e)->CallIntMethod(e, insets, (*e)->GetMethodID(e, windowInsets, "getSystemWindowInsetRight", "()I"));
		*bottom = (*e)->CallIntMethod(e, insets, (*e)->GetMethodID(e, windowInsets, "getSystemWindowInsetBottom", "()I"));
		check(e, "getSystemWindowInset");
	}
}

JNIEXPORT jint JNI_OnLoad(JavaVM *vm, void *reserved) {
	(void)reserved;
	g_vm = vm;
	return JNI_VERSION_1_6;
}

JNIEXPORT void JNICALL Java_dev_metascript_app_NativeApp_start(JNIEnv *e, jclass cls, jobject root) {
	(void)cls;
	if (!g_started) {
		g_started = 1;
		cacheJni(e);
		loopStart();
		MsMain();
	}
	(*e)->PushLocalFrame(e, 32);
	g_root = (*e)->NewGlobalRef(e, root);
	(*e)->CallVoidMethod(e, root, method(e, J.view, "setBackgroundColor", "(I)V"), (jint)0xff000000);
	check(e, "root background");
	jobject context = (*e)->CallObjectMethod(e, root, J.viewGetContext);
	check(e, "getContext");
	g_context = (*e)->NewGlobalRef(e, context);

	jclass contextClass = (*e)->GetObjectClass(e, context);
	jobject resources = (*e)->CallObjectMethod(e, context,
		(*e)->GetMethodID(e, contextClass, "getResources", "()Landroid/content/res/Resources;"));
	check(e, "getResources");
	jobject metrics = (*e)->CallObjectMethod(e, resources,
		(*e)->GetMethodID(e, (*e)->GetObjectClass(e, resources), "getDisplayMetrics", "()Landroid/util/DisplayMetrics;"));
	check(e, "getDisplayMetrics");
	jclass metricsClass = (*e)->GetObjectClass(e, metrics);
	g_density = (*e)->GetFloatField(e, metrics, (*e)->GetFieldID(e, metricsClass, "density", "F"));
	int width = (*e)->GetIntField(e, metrics, (*e)->GetFieldID(e, metricsClass, "widthPixels", "I"));
	int height = (*e)->GetIntField(e, metrics, (*e)->GetFieldID(e, metricsClass, "heightPixels", "I"));
	check(e, "DisplayMetrics fields");
	g_width = width / g_density;
	g_height = height / g_density;

	jobject container = (*e)->NewObject(e, J.frameLayout, J.frameInit, g_context);
	check(e, "container");
	place(e, container, 0, 0, width, height);
	(*e)->CallVoidMethod(e, root, J.groupAddView, container);
	check(e, "addView container");
	g_container = (*e)->NewGlobalRef(e, container);
	(*e)->PopLocalFrame(e, NULL);
	call0(s_mount);
}

JNIEXPORT void JNICALL Java_dev_metascript_app_NativeApp_resize(JNIEnv *e, jclass cls, jint width, jint height) {
	(void)cls;
	if (!g_container) return;
	(*e)->PushLocalFrame(e, 16);
	int left, top, right, bottom;
	systemBarInsets(e, &left, &top, &right, &bottom);
	int w = width - left - right;
	int h = height - top - bottom;
	place(e, g_container, left, top, w, h);
	(*e)->PopLocalFrame(e, NULL);
	g_width = w / g_density;
	g_height = h / g_density;
	call0(s_resize);
}

JNIEXPORT void JNICALL Java_dev_metascript_app_NativeApp_pause(JNIEnv *e, jclass cls) {
	(void)e;
	(void)cls;
}

JNIEXPORT void JNICALL Java_dev_metascript_app_NativeApp_resume(JNIEnv *e, jclass cls) {
	(void)e;
	(void)cls;
}

JNIEXPORT void JNICALL Java_dev_metascript_app_NativeApp_destroy(JNIEnv *e, jclass cls) {
	(void)cls;
	if (!g_container) return;
	call0(s_teardown);
	detach(e, g_container);
	(*e)->DeleteGlobalRef(e, g_container);
	(*e)->DeleteGlobalRef(e, g_context);
	(*e)->DeleteGlobalRef(e, g_root);
	g_container = g_context = g_root = NULL;
}

JNIEXPORT jboolean JNICALL Java_dev_metascript_neon_Touch_touch(JNIEnv *e, jclass cls, jint tag, jint action) {
	(void)e;
	(void)cls;
	enum { ACTION_DOWN = 0, ACTION_UP = 1, ACTION_CANCEL = 3 };
	g_lastTag = tag;
	if (action == ACTION_DOWN) {
		g_lastPhase = 0;
		call0(s_touch);
	} else if (action == ACTION_UP) {
		g_lastPhase = 1;
		call0(s_touch);
		g_lastPhase = 2;
		call0(s_touch);
	} else if (action == ACTION_CANCEL) {
		g_lastPhase = 3;
		call0(s_touch);
	}
	return JNI_TRUE;
}

JNIEXPORT void JNICALL Java_dev_metascript_neon_Scroll_scroll(JNIEnv *e, jclass cls, jint tag, jint phase, jint x, jint y, jint width, jint height, jint contentWidth, jint contentHeight) {
	(void)e;
	(void)cls;
	g_scrollTag = tag;
	g_scrollPhase = phase;
	g_scrollX = x / g_density;
	g_scrollY = y / g_density;
	g_scrollW = width / g_density;
	g_scrollH = height / g_density;
	g_scrollContentW = contentWidth / g_density;
	g_scrollContentH = contentHeight / g_density;
	call0(s_scroll);
}

void niRegisterApp(msClosure mount) { s_mount = mount; }
void niSetResizeHandler(msClosure handler) { s_resize = handler; }
void niSetTeardownHandler(msClosure handler) { s_teardown = handler; }
void niSetLoopHandler(msClosure handler) { s_loop = handler; }
void niSetTouchHandler(msClosure handler) { s_touch = handler; }
int niRunApp(void) { return 0; }
int niLastTouchTag(void) { return g_lastTag; }
int niLastTouchPhase(void) { return g_lastPhase; }
void niSetScrollHandler(msClosure handler) { s_scroll = handler; }
int niLastScrollTag(void) { return g_scrollTag; }
int niLastScrollPhase(void) { return g_scrollPhase; }
float niLastScrollX(void) { return g_scrollX; }
float niLastScrollY(void) { return g_scrollY; }
float niLastScrollWidth(void) { return g_scrollW; }
float niLastScrollHeight(void) { return g_scrollH; }
float niLastScrollContentWidth(void) { return g_scrollContentW; }
float niLastScrollContentHeight(void) { return g_scrollContentH; }
void *niContainerView(void) { return g_container; }
float niScreenWidth(void) { return g_width; }
float niScreenHeight(void) { return g_height; }

static void *newView(jclass cls, jmethodID init) {
	JNIEnv *e = env();
	jobject local = (*e)->NewObject(e, cls, init, g_context);
	check(e, "new view");
	place(e, local, 0, 0, 0, 0);
	jobject global = (*e)->NewGlobalRef(e, local);
	(*e)->DeleteLocalRef(e, local);
	return global;
}

void *niViewCreate(void) {
	return newView(J.frameLayout, J.frameInit);
}

void *niTextCreate(void) {
	jobject label = newView(J.textView, J.textInit);
	JNIEnv *e = env();
	(*e)->CallVoidMethod(e, label, J.textSetTextColor, (jint)0xffffffff);
	(*e)->CallVoidMethod(e, label, J.textSetTextSize, 1, 17.0f);
	check(e, "text defaults");
	return label;
}

void niViewSetTag(void *view, int32_t tag) {
	JNIEnv *e = env();
	jobject boxed = (*e)->CallStaticObjectMethod(e, J.integer, J.integerValueOf, tag);
	(*e)->CallVoidMethod(e, (jobject)view, J.viewSetTag, boxed);
	check(e, "setTag");
	(*e)->DeleteLocalRef(e, boxed);
	jobject listener = (*e)->NewObject(e, J.touch, J.touchInit, tag);
	check(e, "Touch");
	(*e)->CallVoidMethod(e, (jobject)view, J.viewSetOnTouchListener, listener);
	check(e, "setOnTouchListener");
	(*e)->DeleteLocalRef(e, listener);
}

void niViewSetPressable(void *view) {
	JNIEnv *e = env();
	(*e)->CallVoidMethod(e, (jobject)view, J.viewSetClickable, JNI_TRUE);
	check(e, "setClickable");
}

void *niScrollCreate(void) {
	return newView(J.scroll, J.scrollInit);
}

void niScrollSetTag(void *scroll, int32_t tag) {
	JNIEnv *e = env();
	(*e)->CallVoidMethod(e, (jobject)scroll, J.scrollSetTag, tag);
	check(e, "setNeonTag");
}

void niScrollSetOption(void *scroll, const char *name, const char *value) {
	JNIEnv *e = env();
	jstring key = (*e)->NewStringUTF(e, name);
	jstring val = (*e)->NewStringUTF(e, value);
	(*e)->CallVoidMethod(e, (jobject)scroll, J.scrollSetOption, key, val);
	check(e, "setOption");
	(*e)->DeleteLocalRef(e, key);
	(*e)->DeleteLocalRef(e, val);
}

void niScrollSetContentSize(void *scroll, float w, float h) {
	JNIEnv *e = env();
	(*e)->CallVoidMethod(e, (jobject)scroll, J.scrollSetContentSize, px(w), px(h));
	check(e, "setContentSize");
}

void niScrollTo(void *scroll, float x, float y, int animated) {
	JNIEnv *e = env();
	(*e)->CallVoidMethod(e, (jobject)scroll, J.scrollTo, px(x), px(y), animated ? JNI_TRUE : JNI_FALSE);
	check(e, "neonScrollTo");
}

void niAddChild(void *parent, void *child) {
	JNIEnv *e = env();
	detach(e, (jobject)child);
	if ((*e)->IsInstanceOf(e, (jobject)parent, J.scroll)) {
		(*e)->CallVoidMethod(e, (jobject)parent, J.scrollAddContent, (jobject)child);
	} else {
		(*e)->CallVoidMethod(e, (jobject)parent, J.groupAddView, (jobject)child);
	}
	check(e, "addView");
}

void niRemoveFromParent(void *child) {
	detach(env(), (jobject)child);
}

void niViewRelease(void *view) {
	if (view) {
		JNIEnv *e = env();
		if ((*e)->IsInstanceOf(e, (jobject)view, J.scroll)) {
			(*e)->CallVoidMethod(e, (jobject)view, J.scrollDispose);
			check(e, "dispose scroll");
		}
		(*e)->DeleteGlobalRef(e, (jobject)view);
	}
}

void niSetFrame(void *view, float x, float y, float w, float h) {
	int left = px(x);
	int top = px(y);
	place(env(), (jobject)view, left, top, px(x + w) - left, px(y + h) - top);
}

void niSetBackgroundColor(void *view, float r, float g, float b, float a) {
	JNIEnv *e = env();
	jobject drawable = background(e, (jobject)view);
	(*e)->CallVoidMethod(e, drawable, J.drawableSetColor, argb(r, g, b, a));
	check(e, "setColor");
	(*e)->DeleteLocalRef(e, drawable);
}

void niSetCornerRadius(void *view, float radius) {
	JNIEnv *e = env();
	jobject drawable = background(e, (jobject)view);
	(*e)->CallVoidMethod(e, drawable, J.drawableSetCornerRadius, radius * g_density);
	check(e, "setCornerRadius");
	(*e)->DeleteLocalRef(e, drawable);
}

void niSetOpacity(void *view, float opacity) {
	JNIEnv *e = env();
	(*e)->CallVoidMethod(e, (jobject)view, J.viewSetAlpha, opacity);
	check(e, "setAlpha");
}

void niSetText(void *label, const char *s) {
	JNIEnv *e = env();
	jstring text = (*e)->NewStringUTF(e, s ? s : "");
	(*e)->CallVoidMethod(e, (jobject)label, J.textSetText, text);
	check(e, "setText");
	(*e)->DeleteLocalRef(e, text);
}

void niSetTextColor(void *label, float r, float g, float b, float a) {
	JNIEnv *e = env();
	(*e)->CallVoidMethod(e, (jobject)label, J.textSetTextColor, argb(r, g, b, a));
	check(e, "setTextColor");
}

void niSetFont(void *label, float size, int bold) {
	JNIEnv *e = env();
	(*e)->CallVoidMethod(e, (jobject)label, J.textSetTextSize, 1, size);
	(*e)->CallVoidMethod(e, (jobject)label, J.textSetTypeface, bold ? J.typefaceBold : J.typefaceDefault);
	check(e, "setFont");
}

void niMeasureText(void *label, float maxWidth) {
	JNIEnv *e = env();
	int widthSpec = (px(maxWidth) & 0x3fffffff) | (int)0x80000000;
	(*e)->CallVoidMethod(e, (jobject)label, J.viewMeasure, widthSpec, 0);
	int w = (*e)->CallIntMethod(e, (jobject)label, J.viewGetMeasuredWidth);
	int h = (*e)->CallIntMethod(e, (jobject)label, J.viewGetMeasuredHeight);
	check(e, "measure");
	g_measuredW = ceilf(w / g_density);
	g_measuredH = ceilf(h / g_density);
}

float niMeasuredW(void) { return g_measuredW; }
float niMeasuredH(void) { return g_measuredH; }
