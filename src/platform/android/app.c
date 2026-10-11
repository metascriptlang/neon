#include "../native/app.h"
#include <android/log.h>
#include <jni.h>
#include <stdlib.h>
#include <string.h>

JNIEnv *niAndroidEnv(void);
jobject niAndroidContext(void);

static msClosure s_app;
static int g_event;
static char *g_value;
static int g_result;
static char *g_reply;
static jclass g_class;
static jmethodID g_call;

static void fail(JNIEnv *e, const char *op) {
	if (!(*e)->ExceptionCheck(e)) return;
	(*e)->ExceptionDescribe(e);
	__android_log_print(ANDROID_LOG_FATAL, "Neon", "App.%s threw", op);
	abort();
}

static void bind(JNIEnv *e) {
	if (g_class) return;
	jclass local = (*e)->FindClass(e, "dev/metascript/neon/App");
	fail(e, "FindClass");
	g_class = (*e)->NewGlobalRef(e, local);
	(*e)->DeleteLocalRef(e, local);
	g_call = (*e)->GetStaticMethodID(e, g_class, "call",
		"(Landroid/content/Context;Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;");
	fail(e, "call");
}

const char *niAppCall(const char *name, const char *arg) {
	JNIEnv *e = niAndroidEnv();
	bind(e);
	(*e)->PushLocalFrame(e, 8);
	jstring jname = (*e)->NewStringUTF(e, name);
	jstring jarg = (*e)->NewStringUTF(e, arg ? arg : "");
	jstring reply = (jstring)(*e)->CallStaticObjectMethod(e, g_class, g_call, niAndroidContext(), jname, jarg);
	fail(e, name);
	const char *utf = reply ? (*e)->GetStringUTFChars(e, reply, NULL) : NULL;
	free(g_reply);
	g_reply = strdup(utf ? utf : "");
	if (utf) (*e)->ReleaseStringUTFChars(e, reply, utf);
	(*e)->PopLocalFrame(e, NULL);
	return g_reply;
}

void niSetAppHandler(msClosure handler) { s_app = handler; }
int niLastAppEvent(void) { return g_event; }
const char *niLastAppValue(void) { return g_value ? g_value : ""; }
void niSetAppEventResult(int result) { g_result = result; }

JNIEXPORT jint JNICALL Java_dev_metascript_neon_App_event(JNIEnv *e, jclass cls, jint kind, jstring value) {
	(void)cls;
	if (!s_app.fn) return 0;
	const char *utf = value ? (*e)->GetStringUTFChars(e, value, NULL) : NULL;
	free(g_value);
	g_value = strdup(utf ? utf : "");
	if (utf) (*e)->ReleaseStringUTFChars(e, value, utf);
	g_event = kind;
	g_result = 0;
	niInvokeClosure(s_app);
	return g_result;
}
