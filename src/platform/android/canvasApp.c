#include "../../../../void/src/host/androidApp.h"
#include "../native/app.h"
#include <android/log.h>
#include <jni.h>
#include <stdlib.h>

JNIEnv *niAndroidEnv(void) { return voidAndroidEnv(); }

jobject niAndroidContext(void) { return voidAndroidActivity(); }

jclass niAndroidClass(const char *name) {
	JNIEnv *e = voidAndroidEnv();
	jobject loader = voidAndroidClassLoader();
	jmethodID loadClass = (*e)->GetMethodID(e, (*e)->GetObjectClass(e, loader), "loadClass",
		"(Ljava/lang/String;)Ljava/lang/Class;");
	jstring jname = (*e)->NewStringUTF(e, name);
	jclass local = (jclass)(*e)->CallObjectMethod(e, loader, loadClass, jname);
	if ((*e)->ExceptionCheck(e)) {
		(*e)->ExceptionDescribe(e);
		__android_log_print(ANDROID_LOG_FATAL, "Neon", "%s did not load in the canvas app", name);
		abort();
	}
	jclass global = (*e)->NewGlobalRef(e, local);
	(*e)->DeleteLocalRef(e, local);
	(*e)->DeleteLocalRef(e, jname);
	return global;
}

void niInvokeClosure(msClosure c) {
	if (!c.fn) return;
	if (c.env) ((void (*)(void *))c.fn)(c.env);
	else ((void (*)(void))c.fn)();
}
