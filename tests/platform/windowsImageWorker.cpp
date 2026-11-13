#include <windows.h>
#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include "../../src/platform/windows/image.h"

static std::atomic<DWORD> decodeThread{0};
static std::atomic<int> decodeApartment{-1};
static std::atomic<DWORD> wakeThread{0};
static HANDLE processWakeEvent = nullptr;

extern "C" void imageWorkerDecodeProbe(void) {
	APTTYPE apartment;
	APTTYPEQUALIFIER qualifier;
	HRESULT hr = CoGetApartmentType(&apartment, &qualifier);
	decodeApartment.store(SUCCEEDED(hr) ? (int)apartment : -2);
	decodeThread.store(GetCurrentThreadId());
}

extern "C" void imageDecodeJobDoneProbe(uint32_t) {}

extern "C" void ionWakeLoop(void) {
	wakeThread.store(GetCurrentThreadId());
	if (!SetEvent(processWakeEvent)) {
		fprintf(stderr, "image-worker setup: SetEvent failed %lu\n", GetLastError());
		abort();
	}
}

static int failed(const char *message) {
	fprintf(stderr, "image-worker assertion: %s\n", message);
	return 1;
}

int main(int argc, char **argv) {
	if (argc != 2 || strncmp(argv[1], "file://", 7)) {
		fprintf(stderr, "usage: windows-image-worker file://4096x4096.png\n");
		return 2;
	}
	processWakeEvent = CreateEventW(nullptr, FALSE, FALSE, nullptr);
	if (!processWakeEvent) {
		fprintf(stderr, "image-worker setup: CreateEvent failed\n");
		return 2;
	}
	ImageSize header = ImageHeaderSize(argv[1]);
	if (!header.error.empty() || header.width != 4096 || header.height != 4096) {
		fprintf(stderr, "image-worker setup: expected4096x4096 header, got%ux%u: %s\n",
			header.width, header.height, header.error.c_str());
		return 2;
	}
	DWORD hostThread = GetCurrentThreadId();
	ImagePicture picture;
	if (!picture.SetProp("source", argv[1])) return failed("source not accepted");
	printf("image-worker ownership host=%lu decode=%lu apartment=%d\n",
		hostThread, decodeThread.load(), decodeApartment.load());
	if (decodeThread.load() == hostThread) return failed("decode ran on host thread");
	std::string error;
	float width = 0, height = 0;
	if (picture.TakeReport(&error, &width, &height) != kImageNone) {
		return failed("load reported before host result delivery");
	}
	if (WaitForSingleObject(processWakeEvent, 5000) != WAIT_OBJECT_0) {
		return failed("worker completion did not wake host");
	}
	if (!decodeThread.load() || decodeThread.load() == hostThread ||
		decodeApartment.load() != (int)APTTYPE_MTA) {
		return failed("decode did not run in MTA worker");
	}
	if (!wakeThread.load() || wakeThread.load() == hostThread) {
		return failed("completion wake was not from worker");
	}
	int delivered = 0;
	for (const ImageDownload &result : ImageTakeDownloads()) {
		ImagePicture *target = ImagePicture::Waiting(result.id);
		if (target != &picture) return failed("result has no matching live picture");
		target->Deliver(result);
		if (ImagePicture::Waiting(result.id)) return failed("delivered request still waiting");
		delivered++;
	}
	if (delivered != 1) return failed("expected one worker result");
	if (picture.TakeReport(&error, &width, &height) != kImageLoad ||
		width != header.width || height != header.height || !error.empty()) {
		return failed("host did not receive correct load report");
	}
	if (picture.TakeReport(&error, &width, &height) != kImageNone) {
		return failed("load report repeated");
	}
	printf("image-worker passed: MTA decode, worker wake, host delivery, one load report\n");
	return 0;
}
