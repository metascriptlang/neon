#include "../native/app.h"
#include "../native/commands.h"
#include <android/log.h>
#include <jni.h>
#include <stdlib.h>
#include <string.h>

JNIEnv *niAndroidEnv(void);
jobject niAndroidContext(void);
jclass niAndroidClass(const char *name);

static msClosure s_app;
static int g_event;
static char *g_value;
static int g_result;
static char *g_reply;
static void fail(JNIEnv *e, const char *op) {
	if (!(*e)->ExceptionCheck(e)) return;
	(*e)->ExceptionDescribe(e);
	__android_log_print(ANDROID_LOG_FATAL, "Neon", "%s threw", op);
	abort();
}

typedef struct {
	const char *name;
	jclass cls;
	jmethodID call;
} Module;

static const char *callModule(Module *m, const char *name, const char *arg) {
	JNIEnv *e = niAndroidEnv();
	if (!m->cls) {
		m->cls = niAndroidClass(m->name);
		m->call = (*e)->GetStaticMethodID(e, m->cls, "call",
			"(Landroid/content/Context;Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;");
		fail(e, m->name);
	}
	(*e)->PushLocalFrame(e, 8);
	jstring jname = (*e)->NewStringUTF(e, name);
	jstring jarg = (*e)->NewStringUTF(e, arg ? arg : "");
	jstring reply = (jstring)(*e)->CallStaticObjectMethod(e, m->cls, m->call, niAndroidContext(), jname, jarg);
	fail(e, name);
	const char *utf = reply ? (*e)->GetStringUTFChars(e, reply, NULL) : NULL;
	free(g_reply);
	g_reply = strdup(utf ? utf : "");
	if (utf) (*e)->ReleaseStringUTFChars(e, reply, utf);
	(*e)->PopLocalFrame(e, NULL);
	return g_reply;
}

static Module m_app = { "dev.metascript.neon.App" };
static Module m_storage = { "dev.metascript.neon.Storage" };
static Module m_netInfo = { "dev.metascript.neon.NetInfo" };
static Module m_permissions = { "dev.metascript.neon.Permissions" };
static Module m_location = { "dev.metascript.neon.Geolocation" };
static Module m_device = { "dev.metascript.neon.Device" };
static Module m_notifications = { "dev.metascript.neon.Notifications" };

const char *niAppCall(const char *name, const char *arg) { return callModule(&m_app, name, arg); }
const char *niStorageCommand(const char *name, const char *arg) { return callModule(&m_storage, name, arg); }
const char *niNetInfoCommand(const char *name, const char *arg) { return callModule(&m_netInfo, name, arg); }
const char *niPermissionCommand(const char *name, const char *arg) { return callModule(&m_permissions, name, arg); }
const char *niLocationCommand(const char *name, const char *arg) { return callModule(&m_location, name, arg); }
const char *niHapticsCommand(const char *name, const char *arg) { return callModule(&m_device, name, arg); }
const char *niDeviceCommand(const char *name, const char *arg) { return callModule(&m_device, name, arg); }
const char *niLocaleCommand(const char *name, const char *arg) { return callModule(&m_device, name, arg); }
const char *niNotificationCommand(const char *name, const char *arg) { return callModule(&m_notifications, name, arg); }
const char *niClipboardCommand(const char *name, const char *arg) { return niAppCall(name, arg); }
const char *niLinkingCommand(const char *name, const char *arg) { return niAppCall(name, arg); }
const char *niVibrationCommand(const char *name, const char *arg) { return niAppCall(name, arg); }
const char *niAccessibilityCommand(const char *name, const char *arg) { return niAppCall(name, arg); }

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
