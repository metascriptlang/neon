#include "../native/bridge.h"
#include <android/log.h>
#include <jni.h>
#include <math.h>
#include <stdlib.h>

extern void MsMain(void);

static JavaVM *g_vm;
static int g_started;
static msClosure s_mount;
static msClosure s_touch;
static msClosure s_resize;
static msClosure s_teardown;
static int g_lastTag;
static int g_lastPhase;

static jobject g_root;
static jobject g_container;
static jobject g_context;
static float g_density = 1;
static float g_width;
static float g_height;
static float g_measuredW;
static float g_measuredH;

static struct {
	jclass view, viewGroup, frameLayout, layoutParams, textView, gradientDrawable, integer;
	jmethodID viewGetParent, viewSetLayoutParams, viewSetAlpha, viewGetBackground, viewSetBackground;
	jmethodID viewMeasure, viewGetMeasuredWidth, viewGetMeasuredHeight, viewSetTag, viewGetRootWindowInsets;
	jmethodID viewGetContext, groupAddView, groupRemoveView, frameInit, paramsInit;
	jfieldID paramsLeft, paramsTop;
	jmethodID textInit, textSetText, textSetTextColor, textSetTextSize, textSetTypeface;
	jmethodID drawableInit, drawableSetColor, drawableSetCornerRadius, integerValueOf;
	jobject typefaceDefault, typefaceBold;
	int sdk;
} J;

static void call0(msClosure c) {
	if (!c.fn) return;
	if (c.env) ((void (*)(void *))c.fn)(c.env);
	else ((void (*)(void))c.fn)();
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

void niRegisterApp(msClosure mount) { s_mount = mount; }
void niSetResizeHandler(msClosure handler) { s_resize = handler; }
void niSetTeardownHandler(msClosure handler) { s_teardown = handler; }
void niSetTouchHandler(msClosure handler) { s_touch = handler; }
int niRunApp(void) { return 0; }
int niLastTouchTag(void) { return g_lastTag; }
int niLastTouchPhase(void) { return g_lastPhase; }
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

// PARKED: attaching the touch listener waits on ~/metascript/.inbox/compiler/2026-09-23-design-android-java-handoff.md
void niViewSetTag(void *view, int32_t tag) {
	JNIEnv *e = env();
	jobject boxed = (*e)->CallStaticObjectMethod(e, J.integer, J.integerValueOf, tag);
	(*e)->CallVoidMethod(e, (jobject)view, J.viewSetTag, boxed);
	check(e, "setTag");
	(*e)->DeleteLocalRef(e, boxed);
}

void niAddChild(void *parent, void *child) {
	JNIEnv *e = env();
	detach(e, (jobject)child);
	(*e)->CallVoidMethod(e, (jobject)parent, J.groupAddView, (jobject)child);
	check(e, "addView");
}

void niRemoveFromParent(void *child) {
	detach(env(), (jobject)child);
}

void niViewRelease(void *view) {
	if (view) (*env())->DeleteGlobalRef(env(), (jobject)view);
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
