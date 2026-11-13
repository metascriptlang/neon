#include <windows.h>
#include <wincodec.h>
#include <wrl/client.h>
#include <algorithm>
#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <thread>
#include <vector>
#include "../../src/platform/windows/imageDecode.h"
#include "../../src/platform/windows/image.h"

using Microsoft::WRL::ComPtr;

static HANDLE processEntered, processReleased, processFinished, processWake;
static std::atomic<int> entered{0}, finished{0}, active{0}, peak{0}, wakes{0};
static std::atomic<bool> wrongThread{false};
static DWORD hostThread;

static void require(bool value, const char *message) {
	if (!value) {
		fprintf(stderr, "image-decode assertion: %s\n", message);
		exit(1);
	}
}

extern "C" void ionWakeLoop(void) { require(false, "unexpected legacy wake"); }

extern "C" void imageWorkerDecodeProbe(void) {
	APTTYPE apartment;
	APTTYPEQUALIFIER qualifier;
	if (GetCurrentThreadId() == hostThread ||
		FAILED(CoGetApartmentType(&apartment, &qualifier)) || apartment != APTTYPE_MTA) {
		wrongThread.store(true);
	}
	int now = active.fetch_add(1) + 1;
	int old = peak.load();
	while (old < now && !peak.compare_exchange_weak(old, now)) {}
	entered.fetch_add(1);
	SetEvent(processEntered);
	require(WaitForSingleObject(processReleased, 10000) == WAIT_OBJECT_0, "decode gate timed out");
	active.fetch_sub(1);
}

extern "C" void imageDecodeJobDoneProbe(uint32_t) {
	finished.fetch_add(1);
	SetEvent(processFinished);
}

static void postWake(void) {
	wakes.fetch_add(1);
	SetEvent(processWake);
}

static void reset(bool blocked) {
	entered.store(0); finished.store(0); active.store(0); peak.store(0); wakes.store(0);
	wrongThread.store(false);
	ResetEvent(processEntered); ResetEvent(processFinished); ResetEvent(processWake);
	if (blocked) ResetEvent(processReleased); else SetEvent(processReleased);
}

static void waitCount(std::atomic<int> &count, int target, HANDLE event) {
	ULONGLONG deadline = GetTickCount64() + 10000;
	while (count.load() < target) {
		require(GetTickCount64() < deadline, "work count timed out");
		require(WaitForSingleObject(event, 100) != WAIT_FAILED, "event wait failed");
	}
}

static std::string uri(const char *path) {
	std::string value = "file:///";
	value += path;
	std::replace(value.begin(), value.end(), '\\', '/');
	return value;
}

static std::vector<BYTE> reference(const char *path, UINT *width, UINT *height) {
	int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, nullptr, 0);
	require(length > 0, "reference path malformed");
	std::wstring wide((size_t)length, L'\0');
	MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, wide.data(), length);
	ComPtr<IWICImagingFactory> factory;
	ComPtr<IWICBitmapDecoder> decoder;
	ComPtr<IWICBitmapFrameDecode> frame;
	ComPtr<IWICFormatConverter> converter;
	ComPtr<IWICBitmap> bitmap;
	require(SUCCEEDED(CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER,
		IID_PPV_ARGS(&factory))), "reference factory");
	require(SUCCEEDED(factory->CreateDecoderFromFilename(wide.c_str(), nullptr, GENERIC_READ,
		WICDecodeMetadataCacheOnDemand, &decoder)), "reference decoder");
	require(SUCCEEDED(decoder->GetFrame(0, &frame)), "reference frame");
	require(SUCCEEDED(factory->CreateFormatConverter(&converter)), "reference converter");
	require(SUCCEEDED(converter->Initialize(frame.Get(), GUID_WICPixelFormat32bppPBGRA,
		WICBitmapDitherTypeNone, nullptr, 0, WICBitmapPaletteTypeCustom)), "reference conversion");
	require(SUCCEEDED(factory->CreateBitmapFromSource(converter.Get(), WICBitmapCacheOnLoad,
		&bitmap)), "reference bitmap");
	require(SUCCEEDED(bitmap->GetSize(width, height)), "reference dimensions");
	std::vector<BYTE> bytes((size_t)*width * *height * 4);
	require(SUCCEEDED(bitmap->CopyPixels(nullptr, *width * 4, (UINT)bytes.size(), bytes.data())),
		"reference pixels");
	return bytes;
}

int main(int argc, char **argv) {
	if (argc != 3) {
		fprintf(stderr, "usage: windows-image-decode native-64.png native-4096.png\n");
		return 2;
	}
	require(SUCCEEDED(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED)), "main STA initialization");
	hostThread = GetCurrentThreadId();
	require(ImageDecodeByteCount(1, 1) == 4 && ImageDecodeByteCount(16384, 16384) == 1073741824,
		"valid byte counts");
	require(!ImageDecodeByteCount(0, 1) && !ImageDecodeByteCount(UINT32_MAX, 1) &&
		!ImageDecodeByteCount(0x80000000u, 0x80000000u) &&
		!ImageDecodeByteCount(UINT32_MAX, UINT32_MAX), "overflowing byte count accepted");
	processEntered = CreateEventW(nullptr, FALSE, FALSE, nullptr);
	processReleased = CreateEventW(nullptr, TRUE, FALSE, nullptr);
	processFinished = CreateEventW(nullptr, FALSE, FALSE, nullptr);
	processWake = CreateEventW(nullptr, FALSE, FALSE, nullptr);
	require(processEntered && processReleased && processFinished && processWake, "process events");
	std::string small = uri(argv[1]), large = uri(argv[2]);
	ImageSize rejected = ImageHeaderSize((small + "%00ignored.png").c_str());
	require(!rejected.error.empty(), "encoded NUL URI silently loaded prefix file");
	printf("image-decode URI/byte-range guards passed\n");

	for (const char *path : {argv[1], argv[2]}) {
		reset(false);
		UINT width = 0, height = 0;
		auto expected = reference(path, &width, &height);
		UINT wanted = path == argv[1] ? 64 : 4096;
		require(width == wanted && height == wanted, "fixture dimensions must be64 and4096");
		ImageDecoded owned;
		{
			ImageDecodeQueue queue(postWake);
			uint32_t id = queue.Submit(uri(path).c_str());
			waitCount(finished, 1, processFinished);
			require(queue.Inspect().reservedBytes == expected.size(), "ready pixels escaped byte reservation");
			auto results = queue.Take();
			require(results.size() == 1 && results[0].id == id, "one matching result");
			owned = std::move(results[0]);
			queue.Close();
		}
		require(!wrongThread.load() && wakes.load() == 1, "MTA decode and one completion wake");
		require(owned.error.empty() && owned.width == width && owned.height == height &&
			owned.byteCount == expected.size() && owned.pixels, "owned result dimensions");
		require(!memcmp(owned.pixels.get(), expected.data(), expected.size()),
			"pixels differ after queue close/destruction");
		printf("image-decode pixels %ux%u all-bytes-equal after-close=1\n", width, height);
	}

	reset(true);
	{
		ImageDecodeQueue queue(postWake);
		for (int i = 0; i < 3; i++) queue.Submit(small.c_str());
		waitCount(entered, 2, processEntered);
		require(queue.Inspect().workers == 2 && entered.load() == 2 && peak.load() == 2,
			"two-worker cap while blocked");
		SetEvent(processReleased);
		waitCount(finished, 3, processFinished);
		require(queue.Take().size() == 3 && peak.load() <= 2, "bounded work completes");
	}
	printf("image-decode worker-cap passed\n");

	reset(true);
	{
		ImageDecodeQueue queue(postWake);
		queue.Submit(small.c_str());
		queue.Submit(small.c_str());
		waitCount(entered, 2, processEntered);
		uint32_t canceled = queue.Submit(small.c_str());
		queue.Cancel(canceled);
		SetEvent(processReleased);
		waitCount(finished, 3, processFinished);
		auto results = queue.Take();
		require(results.size() == 2 && entered.load() == 2 && wakes.load() == 2,
			"canceled queued work decoded or published");
	}
	printf("image-decode cancel-queued passed\n");

	reset(true);
	{
		ImageDecodeQueue queue(postWake);
		queue.Submit(large.c_str());
		waitCount(entered, 1, processEntered);
		queue.Submit(large.c_str());
		ULONGLONG deadline = GetTickCount64() + 10000;
		while (!queue.Inspect().waitingForBytes && entered.load() == 1) {
			require(GetTickCount64() < deadline, "second admission did not reach byte budget");
			Sleep(1);
		}
		require(queue.Inspect().waitingForBytes == 1 && entered.load() == 1,
			"one oversized decode admitted alone");
		SetEvent(processReleased);
		waitCount(finished, 1, processFinished);
		require(queue.Inspect().reservedBytes == 4096u * 4096u * 4u,
			"ready oversized pixels lost reservation");
		require(queue.Take().size() == 1, "first oversized result handoff");
		waitCount(finished, 2, processFinished);
		require(queue.Take().size() == 1 && peak.load() == 1 && !queue.Inspect().reservedBytes,
			"oversized budget completes after handoff");
	}
	printf("image-decode byte-budget passed\n");

	reset(true);
	{
		ImageDecodeQueue queue(postWake);
		uint32_t stale = queue.Submit(large.c_str());
		waitCount(entered, 1, processEntered);
		queue.Cancel(stale);
		uint32_t current = queue.Submit(small.c_str());
		SetEvent(processReleased);
		waitCount(finished, 2, processFinished);
		auto results = queue.Take();
		require(results.size() == 1 && results[0].id == current && wakes.load() == 1,
			"canceled/replaced source published");
	}
	printf("image-decode cancel-replace passed\n");

	reset(true);
	{
		ImageDecodeQueue queue(postWake);
		uint32_t id = queue.Submit(small.c_str());
		waitCount(entered, 1, processEntered);
		SetEvent(processReleased);
		waitCount(finished, 1, processFinished);
		queue.Cancel(id);
		require(queue.Take().empty(), "cancel after publication not filtered");
	}
	printf("image-decode cancel-ready passed\n");

	reset(false);
	{
		ImageDecodeQueue queue(postWake);
		uint32_t id = queue.Submit("unsupported:fixture");
		waitCount(finished, 1, processFinished);
		auto results = queue.Take();
		require(results.size() == 1 && results[0].id == id && !results[0].error.empty() &&
			!results[0].pixels && !queue.Inspect().reservedBytes && wakes.load() == 1,
			"decode failure lost its error/completion");
	}
	printf("image-decode error-delivery passed\n");

	reset(false);
	{
		ImageDecodeQueue queue(postWake);
		queue.Submit(large.c_str());
		waitCount(finished, 1, processFinished);
		queue.Close();
		require(queue.Take().empty(), "closed queue delivered ready pixels");
		ULONGLONG deadline = GetTickCount64() + 10000;
		while (queue.Inspect().reservedBytes) {
			require(GetTickCount64() < deadline, "closed ready pixels retained reservation");
			Sleep(1);
		}
		require(wakes.load() == 1, "close of ready queue emitted extra wake");
	}
	printf("image-decode close-ready passed\n");

	reset(true);
	{
		ImageDecodeQueue queue(postWake);
		queue.Submit(large.c_str());
		waitCount(entered, 1, processEntered);
		HANDLE returned = CreateEventW(nullptr, TRUE, FALSE, nullptr);
		std::atomic<bool> forced{false};
		std::thread release([&] {
			if (WaitForSingleObject(returned, 3000) != WAIT_OBJECT_0) forced.store(true);
			SetEvent(processReleased);
		});
		queue.Close();
		SetEvent(returned);
		release.join();
		waitCount(finished, 1, processFinished);
		require(!forced.load(), "close waited for gated decoder");
		require(queue.Take().empty() && wakes.load() == 0, "late result/wake after close");
		CloseHandle(returned);
	}
	printf("image-decode nonblocking-close/no-late-wake passed\n");
	return 0;
}
