#include <windows.h>
#include <d3d11.h>
#include <d2d1_1.h>
#include <wrl/client.h>
#include <algorithm>
#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <optional>
#include <mutex>
#include <string>
#include <vector>
#include "../../src/platform/windows/image.h"

using Microsoft::WRL::ComPtr;
static DWORD host;
static HANDLE enteredEvent, releasedEvent, finishedEvent, wakeEvent;
static std::atomic<int> entered{0}, finished{0}, wakes{0};
static std::atomic<bool> wrongThread{false};
static std::mutex finishedLock;
static std::vector<uint32_t> finishedIds;

static void require(bool ok, const char *message) {
	if (!ok) {
		fprintf(stderr, "image-consumer assertion: %s\n", message);
		fflush(stderr);
		_Exit(1);
	}
}

static void check(HRESULT hr, const char *message) { require(SUCCEEDED(hr), message); }

extern "C" void ionWakeLoop(void) {
	wakes.fetch_add(1);
	SetEvent(wakeEvent);
}

extern "C" void imageWorkerDecodeProbe(void) {
	APTTYPE type;
	APTTYPEQUALIFIER qualifier;
	if (GetCurrentThreadId() == host || FAILED(CoGetApartmentType(&type, &qualifier)) || type != APTTYPE_MTA)
		wrongThread.store(true);
	entered.fetch_add(1);
	SetEvent(enteredEvent);
	require(WaitForSingleObject(releasedEvent, 10000) == WAIT_OBJECT_0, "decode gate timed out");
}

extern "C" void imageDecodeJobDoneProbe(uint32_t id) {
	std::lock_guard<std::mutex> lock(finishedLock);
	finishedIds.push_back(id);
	finished.store((int)finishedIds.size());
	SetEvent(finishedEvent);
}

static void wait(std::atomic<int> &count, int target, HANDLE event) {
	ULONGLONG deadline = GetTickCount64() + 10000;
	while (count.load() < target) {
		require(GetTickCount64() < deadline, "work count timed out");
		require(WaitForSingleObject(event, 100) != WAIT_FAILED, "event wait failed");
	}
}

static ImageReport report(ImagePicture &picture, float wantedWidth, float wantedHeight) {
	std::string error;
	float width = -1, height = -1;
	ImageReport result = picture.TakeReport(&error, &width, &height);
	if (result != kImageNone) {
		require(GetCurrentThreadId() == host, "report not on host thread");
		require(width == wantedWidth && height == wantedHeight, "report dimensions");
		require((result == kImageError) == !error.empty(), "report error payload");
	}
	return result;
}

static std::string uri(const char *path) {
	std::string value = "file:///" + std::string(path);
	std::replace(value.begin(), value.end(), '\\', '/');
	return value;
}

struct Surface : IDrawingSurface {
	ComPtr<ID2D1DeviceContext> dc;
	ComPtr<ID2D1Bitmap1> target, readback;
	UINT width, height;
	Surface(ID2D1DeviceContext *context, UINT w, UINT h) : dc(context), width(w), height(h) {
		auto format = D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_PREMULTIPLIED);
		auto targetProps = D2D1::BitmapProperties1(D2D1_BITMAP_OPTIONS_TARGET | D2D1_BITMAP_OPTIONS_CANNOT_DRAW, format, 96, 96);
		auto readProps = D2D1::BitmapProperties1(D2D1_BITMAP_OPTIONS_CPU_READ | D2D1_BITMAP_OPTIONS_CANNOT_DRAW, format, 96, 96);
		check(dc->CreateBitmap(D2D1::SizeU(w, h), nullptr, 0, &targetProps, &target), "owned target");
		check(dc->CreateBitmap(D2D1::SizeU(w, h), nullptr, 0, &readProps, &readback), "owned readback");
	}
	void *BeginDrawD2D(float dpi) override {
		dc->SetTarget(target.Get()); dc->SetDpi(dpi, dpi); dc->BeginDraw(); return dc.Get();
	}
	void EndDraw() override { check(dc->EndDraw(), "production Draw EndDraw"); }
	std::vector<BYTE> Read() {
		check(readback->CopyFromBitmap(nullptr, target.Get(), nullptr), "owned readback copy");
		D2D1_MAPPED_RECT mapped;
		check(readback->Map(D2D1_MAP_OPTIONS_READ, &mapped), "owned readback map");
		require(mapped.pitch >= width * 4, "owned readback pitch");
		std::vector<BYTE> result((size_t)width * height * 4);
		for (UINT row = 0; row < height; row++)
			memcpy(result.data() + (size_t)row * width * 4, mapped.bits + (size_t)row * mapped.pitch, width * 4);
		check(readback->Unmap(), "owned readback unmap");
		return result;
	}
};

struct Visual : IVisual {
	Surface *surface = nullptr;
	void Content(IDrawingSurface *value) override { surface = static_cast<Surface *>(value); }
	void InsertAt(IVisual *, int32_t) override {}
	void Remove(IVisual *) override {}
	void Opacity(float) override {}
	void TransformMatrix(const float[6]) override {}
	void AnimatedOpacity(const Curve &, double) override {}
	void FramedTransform(const float[6], const float[6]) override {}
	void MotionTransform(const float[6]) override {}
	void AnimatedTransform(const Curve[6], double) override {}
	void Size(float, float) override {}
	void Offset(float, float) override {}
	void CornerRadius(float) override {}
	void ClipsChildren(bool) override {}
	void Brush(Color) override {}
};

struct Context : ICompositionContext {
	ComPtr<ID2D1DeviceContext> dc;
	Context() {
		ComPtr<ID3D11Device> gpu;
		check(D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_WARP, nullptr, D3D11_CREATE_DEVICE_BGRA_SUPPORT,
			nullptr, 0, D3D11_SDK_VERSION, &gpu, nullptr, nullptr), "WARP device");
		ComPtr<IDXGIDevice> dxgi; check(gpu.As(&dxgi), "DXGI device");
		ComPtr<ID2D1Factory1> factory;
		check(D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED, __uuidof(ID2D1Factory1),
			nullptr, (void **)factory.GetAddressOf()), "D2D factory");
		ComPtr<ID2D1Device> drawing; check(factory->CreateDevice(dxgi.Get(), &drawing), "D2D device");
		check(drawing->CreateDeviceContext(D2D1_DEVICE_CONTEXT_OPTIONS_NONE, &dc), "D2D context");
	}
	IVisual *CreateSpriteVisual() override { return new Visual(); }
	IDrawingSurface *CreateDrawingSurface(int32_t w, int32_t h) override { return new Surface(dc.Get(), w, h); }
	void Commit() override {}
};

int main(int argc, char **argv) {
	if (argc != 2) return 2;
	check(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED), "host STA");
	host = GetCurrentThreadId();
	enteredEvent = CreateEventW(nullptr, FALSE, FALSE, nullptr);
	releasedEvent = CreateEventW(nullptr, TRUE, FALSE, nullptr);
	finishedEvent = CreateEventW(nullptr, FALSE, FALSE, nullptr);
	wakeEvent = CreateEventW(nullptr, FALSE, FALSE, nullptr);
	require(enteredEvent && releasedEvent && finishedEvent && wakeEvent, "event setup");
	std::string source = uri(argv[1]);
	ImageSize size = ImageHeaderSize(source.c_str());
	require(size.error.empty() && size.width == 64 && size.height == 64, "valid64 header");
	std::optional<ImagePicture> picture;
	picture.emplace();
	picture->SetProp("source", source.c_str());
	require(report(*picture, 0, 0) == kImageNone, "local load reported synchronously");
	wait(entered, 1, enteredEvent);
	picture.reset();
	picture.emplace();
	picture->SetProp("source", source.c_str());
	wait(entered, 2, enteredEvent);
	SetEvent(releasedEvent);
	wait(finished, 2, finishedEvent);
	auto decoded = ImageTakeDecoded();
	require(decoded.size() == 1 && ImagePicture::Waiting(decoded[0].id) == &*picture,
		"destroy/reuse delivered to wrong picture");
	{
		std::lock_guard<std::mutex> lock(finishedLock);
		for (uint32_t id : finishedIds) {
			if (id != decoded[0].id) require(!ImagePicture::Waiting(id), "destroyed request retained an owner");
		}
	}
	require(decoded[0].error.empty() && decoded[0].width == 64 && decoded[0].height == 64 && decoded[0].byteCount == 64 * 64 * 4,
		"decoded result payload");
	std::vector<BYTE> expected(decoded[0].pixels.get(), decoded[0].pixels.get() + decoded[0].byteCount);
	uint32_t deliveredId = decoded[0].id;
	picture->Deliver(std::move(decoded[0]));
	require(!ImagePicture::Waiting(deliveredId) && report(*picture, 64, 64) == kImageLoad &&
		report(*picture, 0, 0) == kImageNone, "exactly one load report");
	Context context;
	Visual visual;
	picture->Draw(&context, &visual, 64, 64, 1);
	require(visual.surface && visual.surface->Read() == expected, "production Draw pixels differ from worker buffer");
	printf("image-consumer destroy/reuse/main-adoption/production-Draw64 passed\n");

	picture->SetProp("source", "");
	picture->SetProp("source", source.c_str());
	wait(finished, 3, finishedEvent);
	picture->SetProp("source", "");
	require(ImageTakeDecoded().empty(), "ready canceled image delivered");
	picture->SetProp("source", source.c_str());
	wait(finished, 4, finishedEvent);
	auto stale = ImageTakeDecoded();
	require(stale.size() == 1, "stale batch setup");
	picture->SetProp("source", (source + ".missing").c_str());
	require(!ImagePicture::Waiting(stale[0].id), "taken stale result still has owner");
	require(report(*picture, 0, 0) == kImageNone, "error reported synchronously");
	wait(finished, 5, finishedEvent);
	auto errors = ImageTakeDecoded();
	require(errors.size() == 1 && !errors[0].error.empty() && ImagePicture::Waiting(errors[0].id) == &*picture,
		"replacement error routed incorrectly");
	picture->Deliver(std::move(errors[0]));
	require(report(*picture, 0, 0) == kImageError && report(*picture, 0, 0) == kImageNone,
		"exactly one async error report");
	printf("image-consumer ready-cancel/taken-stale/replacement/error passed\n");

	ResetEvent(releasedEvent);
	picture->SetProp("source", source.c_str());
	wait(entered, 5, enteredEvent);
	ImagePicture other;
	other.SetProp("source", source.c_str());
	wait(entered, 6, enteredEvent);
	ImagePicture queued;
	queued.SetProp("source", source.c_str());
	int before = wakes.load();
	ULONGLONG closingAt = GetTickCount64();
	ImageShutdown();
	require(GetTickCount64() - closingAt < 500, "shutdown waited for blocked decode");
	SetEvent(releasedEvent);
	wait(finished, 7, finishedEvent);
	require(ImageTakeDecoded().empty() && wakes.load() == before, "shutdown allowed result or late wake");
	require(report(*picture, 0, 0) == kImageNone && report(other, 0, 0) == kImageNone &&
		report(queued, 0, 0) == kImageNone, "shutdown reported canceled work");
	require(!wrongThread.load(), "decode ran on host or outside MTA");
	printf("image-consumer nonblocking-shutdown/no-late-wake passed; kernel-event fixture, not Ion app proof\n");
	return 0;
}
