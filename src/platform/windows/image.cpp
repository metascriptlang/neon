#include <windows.h>
#include <urlmon.h>
#include <d2d1_1.h>
#include <d2d1effects.h>
#include <wincodec.h>
#include <wrl/client.h>
#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <mutex>
#include <vector>
#include <atomic>
#include <condition_variable>
#include <deque>
#include <limits>
#include <new>
#include "image.h"
#include "imageDecode.h"
#include "must.h"

using Microsoft::WRL::ComPtr;

extern "C" void ionWakeLoop(void);

#ifdef NEON_IMAGE_WORKER_TEST
extern "C" void imageWorkerDecodeProbe(void);
extern "C" void imageDecodeJobDoneProbe(uint32_t id);
#endif

namespace {

IWICImagingFactory *factory() {
	static IWICImagingFactory *shared = nullptr;
	if (!shared) {
		HRESULT init = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
		if (FAILED(init) && init != RPC_E_CHANGED_MODE) must(init, "CoInitializeEx");
		must(CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&shared)), "CLSID_WICImagingFactory");
	}
	return shared;
}

[[noreturn]] void refuse(const char *what, const char *value) {
	fprintf(stderr, "neon windows bridge: %s \"%s\"\n", what, value);
	fflush(stderr);
	abort();
}

std::string loadError(const char *what, HRESULT hr) {
	char message[160];
	snprintf(message, sizeof message, "%s, HRESULT 0x%08lx", what, (unsigned long)hr);
	return message;
}

std::string systemText(HRESULT hr) {
	char text[200];
	DWORD length = FormatMessageA(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_FROM_HMODULE | FORMAT_MESSAGE_IGNORE_INSERTS,
		GetModuleHandleW(L"urlmon.dll"), (DWORD)hr, 0, text, sizeof text, nullptr);
	while (length > 0 && (text[length - 1] == '\r' || text[length - 1] == '\n' || text[length - 1] == ' ')) length--;
	return length ? std::string(text, length) : "unknown error";
}

std::mutex g_downloadsLock;
std::vector<ImageDownload> g_downloads;
std::map<uint32_t, ImagePicture *> g_waiting;
std::atomic<uint32_t> g_nextImageId{1};

uint32_t imageRequestId() {
	uint32_t id = g_nextImageId.load(std::memory_order_relaxed);
	for (;;) {
		if (!id) refuse("image request", "request id exhausted");
		if (g_nextImageId.compare_exchange_weak(id, id + 1, std::memory_order_relaxed)) return id;
	}
}

struct FetchJob {
	uint32_t id;
	std::string uri;
};

// A worker thread downloads into the URL cache and queues the result; only ionWakeLoop is called from it, and the host
// thread takes the queue from its wake handler (niwDrainImages).
DWORD WINAPI fetchWorker(void *arg) {
	std::unique_ptr<FetchJob> job(static_cast<FetchJob *>(arg));
	ImageDownload done;
	done.id = job->id;
	HRESULT init = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
	int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, job->uri.c_str(), -1, nullptr, 0);
	if (length == 0) {
		done.error = "malformed URI";
	} else {
		std::wstring wide((size_t)length, L'\0');
		MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, job->uri.c_str(), -1, &wide[0], length);
		wchar_t path[MAX_PATH];
		HRESULT hr = URLDownloadToCacheFileW(nullptr, wide.c_str(), path, MAX_PATH, 0, nullptr);
		if (FAILED(hr)) done.error = loadError(("network request failed: " + systemText(hr)).c_str(), hr);
		else done.path = path;
	}
	if (SUCCEEDED(init)) CoUninitialize();
	{
		std::lock_guard<std::mutex> lock(g_downloadsLock);
		g_downloads.push_back(std::move(done));
	}
	ionWakeLoop();
	return 0;
}

int hexValue(char c) {
	if (c >= '0' && c <= '9') return c - '0';
	if (c >= 'a' && c <= 'f') return c - 'a' + 10;
	if (c >= 'A' && c <= 'F') return c - 'A' + 10;
	return -1;
}

std::string percentDecoded(const char *text) {
	std::string decoded;
	for (const char *at = text; *at; at++) {
		int high = at[0] == '%' && at[1] ? hexValue(at[1]) : -1;
		int low = high >= 0 && at[2] ? hexValue(at[2]) : -1;
		if (low >= 0) {
			decoded += (char)(high * 16 + low);
			at += 2;
		} else {
			decoded += *at;
		}
	}
	return decoded;
}

bool base64Decoded(const char *text, std::vector<BYTE> *bytes) {
	uint32_t bits = 0;
	int count = 0;
	for (const char *at = text; *at && *at != '='; at++) {
		int value = *at >= 'A' && *at <= 'Z' ? *at - 'A' : *at >= 'a' && *at <= 'z' ? *at - 'a' + 26 :
			*at >= '0' && *at <= '9' ? *at - '0' + 52 : *at == '+' ? 62 : *at == '/' ? 63 : -1;
		if (value < 0) return false;
		bits = bits << 6 | (uint32_t)value;
		if (++count == 4) {
			bytes->push_back((BYTE)(bits >> 16));
			bytes->push_back((BYTE)(bits >> 8));
			bytes->push_back((BYTE)bits);
			bits = 0;
			count = 0;
		}
	}
	if (count == 1) return false;
	if (count == 2) bytes->push_back((BYTE)(bits >> 4));
	if (count == 3) {
		bytes->push_back((BYTE)(bits >> 10));
		bytes->push_back((BYTE)(bits >> 2));
	}
	return true;
}

bool startsWith(const char *text, const char *prefix) { return strncmp(text, prefix, strlen(prefix)) == 0; }

// The WIC decoder of a source, or an error naming why it has none.
HRESULT openDecoder(IWICImagingFactory *wic, const char *uri, std::vector<BYTE> *data, ComPtr<IWICBitmapDecoder> *decoder, std::string *error) {
	if (startsWith(uri, "file://")) {
		std::string path = percentDecoded(uri + 7);
		if (path.size() > 2 && path[0] == '/' && path[2] == ':') path.erase(0, 1);
		if (path.find('\0') != std::string::npos) {
			*error = "malformed URI";
			return E_INVALIDARG;
		}
		int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path.c_str(), -1, nullptr, 0);
		if (length == 0) {
			*error = "malformed URI";
			return E_INVALIDARG;
		}
		std::wstring wide((size_t)length, L'\0');
		MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path.c_str(), -1, &wide[0], length);
		HRESULT hr = wic->CreateDecoderFromFilename(wide.c_str(), nullptr, GENERIC_READ, WICDecodeMetadataCacheOnDemand, decoder->GetAddressOf());
		if (FAILED(hr)) *error = loadError(hr == HRESULT_FROM_WIN32(ERROR_FILE_NOT_FOUND) || hr == HRESULT_FROM_WIN32(ERROR_PATH_NOT_FOUND) ? "file not found" : "cannot open image", hr);
		return hr;
	}
	if (startsWith(uri, "data:")) {
		const char *comma = strchr(uri, ',');
		std::string header = comma ? std::string(uri, comma) : "";
		if (!comma || header.size() < 7 || header.compare(header.size() - 7, 7, ";base64") != 0 || !base64Decoded(comma + 1, data)) {
			*error = "unsupported data URI";
			return E_INVALIDARG;
		}
		if (data->size() > std::numeric_limits<DWORD>::max()) {
			*error = "data URI exceeds WIC stream limit";
			return E_INVALIDARG;
		}
		ComPtr<IWICStream> stream;
		HRESULT hr = wic->CreateStream(&stream);
		if (SUCCEEDED(hr)) hr = stream->InitializeFromMemory(data->data(), (DWORD)data->size());
		if (SUCCEEDED(hr)) hr = wic->CreateDecoderFromStream(stream.Get(), nullptr, WICDecodeMetadataCacheOnDemand, decoder->GetAddressOf());
		if (FAILED(hr)) *error = loadError("cannot decode image", hr);
		return hr;
	}
	*error = "unsupported URI scheme";
	return E_NOTIMPL;
}

bool isNetwork(const char *uri) { return startsWith(uri, "http://") || startsWith(uri, "https://"); }

ImageSize frameSize(HRESULT opened, IWICBitmapDecoder *decoder, std::string error) {
	ImageSize size;
	ComPtr<IWICBitmapFrameDecode> frame;
	HRESULT hr = opened;
	if (SUCCEEDED(hr)) hr = decoder->GetFrame(0, &frame);
	if (SUCCEEDED(hr)) hr = frame->GetSize(&size.width, &size.height);
	if (FAILED(hr)) size.error = error.empty() ? loadError("cannot decode image", hr) : error;
	return size;
}

}

size_t ImageDecodeByteCount(uint32_t width, uint32_t height) {
	uint64_t pixels = (uint64_t)width * height;
	if (!width || !height || pixels > std::numeric_limits<UINT>::max() / 4) return 0;
	return (size_t)(pixels * 4);
}

struct ImageDecodeQueue::State : std::enable_shared_from_this<ImageDecodeQueue::State> {
	static constexpr uint32_t workerLimit = 2;
	static constexpr size_t byteBudget = 30 * 1024 * 1024;
	struct Job {
		uint32_t id = 0;
		std::string uri;
		std::atomic<bool> canceled{false};
	};
	struct Ready { std::shared_ptr<Job> job; ImageDecoded image; };
	std::mutex mutex;
	std::condition_variable changed;
	std::deque<std::shared_ptr<Job>> queued;
	std::map<uint32_t, std::shared_ptr<Job>> jobs;
	std::vector<Ready> ready;
	void (*postWake)(void);
	std::atomic<bool> closing{false};
	bool started = false;
	size_t activeBytes = 0;
#ifdef NEON_IMAGE_WORKER_TEST
	uint32_t workers = 0;
	size_t waitingForBytes = 0;
#endif

	explicit State(void (*wake)(void)) : postWake(wake) {
		if (!wake) refuse("image decode queue", "missing postWake");
	}

	bool acquire(size_t bytes, const std::shared_ptr<Job> &job) {
		std::unique_lock<std::mutex> lock(mutex);
#ifdef NEON_IMAGE_WORKER_TEST
		waitingForBytes++;
#endif
		changed.wait(lock, [&] {
			return closing || job->canceled.load() || activeBytes == 0 ||
				(activeBytes <= byteBudget && bytes <= byteBudget - activeBytes);
		});
#ifdef NEON_IMAGE_WORKER_TEST
		waitingForBytes--;
#endif
		if (closing || job->canceled.load()) return false;
		activeBytes += bytes;
		return true;
	}

	void release(size_t bytes) {
		{
			std::lock_guard<std::mutex> lock(mutex);
			activeBytes -= bytes;
		}
		changed.notify_all();
	}

	ImageDecoded decode(IWICImagingFactory *wic, const std::shared_ptr<Job> &job) {
		ImageDecoded result;
		result.id = job->id;
		if (job->canceled.load()) return result;
		std::vector<BYTE> data;
		ComPtr<IWICBitmapDecoder> decoder;
		ComPtr<IWICBitmapFrameDecode> frame;
		ComPtr<IWICFormatConverter> converter;
		HRESULT hr = openDecoder(wic, job->uri.c_str(), &data, &decoder, &result.error);
		UINT width = 0, height = 0;
		if (SUCCEEDED(hr)) hr = decoder->GetFrame(0, &frame);
		if (SUCCEEDED(hr)) hr = frame->GetSize(&width, &height);
		if (FAILED(hr)) {
			if (result.error.empty()) result.error = loadError("cannot decode image", hr);
			return result;
		}
		size_t bytes = ImageDecodeByteCount(width, height);
		if (!bytes) {
			result.error = "decoded image dimensions exceed WIC buffer limit";
			return result;
		}
		if (!acquire(bytes, job)) return result;
#ifdef NEON_IMAGE_WORKER_TEST
		imageWorkerDecodeProbe();
#endif
		if (!closing.load() && !job->canceled.load()) {
			result.pixels.reset(new (std::nothrow) uint8_t[bytes]);
			if (!result.pixels) hr = E_OUTOFMEMORY;
			if (SUCCEEDED(hr)) hr = wic->CreateFormatConverter(&converter);
			if (SUCCEEDED(hr)) hr = converter->Initialize(frame.Get(), GUID_WICPixelFormat32bppPBGRA,
				WICBitmapDitherTypeNone, nullptr, 0, WICBitmapPaletteTypeCustom);
			if (SUCCEEDED(hr)) hr = converter->CopyPixels(nullptr, width * 4, (UINT)bytes, result.pixels.get());
			if (FAILED(hr)) {
				result.pixels.reset();
				result.error = loadError("cannot decode image", hr);
			} else {
				result.width = width;
				result.height = height;
				result.byteCount = bytes;
			}
		}
		if (!result.byteCount) release(bytes);
		return result;
	}

	void finish(const std::shared_ptr<Job> &job, ImageDecoded result) {
		std::lock_guard<std::mutex> lock(mutex);
		if (closing || job->canceled.load()) {
			activeBytes -= result.byteCount;
			changed.notify_all();
			jobs.erase(job->id);
			return;
		}
		ready.push_back({job, std::move(result)});
		postWake();
	}

	static DWORD WINAPI run(void *arg) {
		std::unique_ptr<std::shared_ptr<State>> given(static_cast<std::shared_ptr<State> *>(arg));
		std::shared_ptr<State> self = std::move(*given);
		given.reset();
		must(CoInitializeEx(nullptr, COINIT_MULTITHREADED), "image decode MTA");
		ComPtr<IWICImagingFactory> wic;
		must(CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER,
			IID_PPV_ARGS(&wic)), "image decode WIC factory");
		for (;;) {
			std::shared_ptr<Job> job;
			std::deque<std::shared_ptr<Job>> discardedQueue;
			std::map<uint32_t, std::shared_ptr<Job>> discardedJobs;
			std::vector<Ready> discardedReady;
			bool stop = false;
			{
				std::unique_lock<std::mutex> lock(self->mutex);
				self->changed.wait(lock, [&] { return self->closing || !self->queued.empty(); });
				if (self->closing) {
					self->queued.swap(discardedQueue);
					self->jobs.swap(discardedJobs);
					self->ready.swap(discardedReady);
					for (auto &entry : discardedReady) self->activeBytes -= entry.image.byteCount;
					stop = true;
				} else {
					job = std::move(self->queued.front());
					self->queued.pop_front();
				}
			}
			if (stop) break;
			self->finish(job, self->decode(wic.Get(), job));
#ifdef NEON_IMAGE_WORKER_TEST
			imageDecodeJobDoneProbe(job->id);
#endif
		}
		wic.Reset();
		CoUninitialize();
		return 0;
	}

	void start() {
		if (started) return;
		started = true;
		for (uint32_t i = 0; i < workerLimit; i++) {
			auto owner = new std::shared_ptr<State>(shared_from_this());
			HANDLE thread = CreateThread(nullptr, 0, run, owner, 0, nullptr);
			if (!thread) {
				DWORD error = GetLastError();
				delete owner;
				must(HRESULT_FROM_WIN32(error), "image decode CreateThread");
			}
			CloseHandle(thread);
#ifdef NEON_IMAGE_WORKER_TEST
			workers++;
#endif
		}
	}
};

ImageDecodeQueue::ImageDecodeQueue(void (*postWake)(void)) : state(std::make_shared<State>(postWake)) {}
ImageDecodeQueue::~ImageDecodeQueue() { Close(); }

uint32_t ImageDecodeQueue::Submit(const char *uri) {
	auto job = std::make_shared<State::Job>();
	job->uri = uri;
	std::lock_guard<std::mutex> lock(state->mutex);
	if (state->closing) refuse("image decode queue", "submit after close");
	job->id = imageRequestId();
	state->jobs[job->id] = job;
	state->queued.push_back(job);
	state->start();
	state->changed.notify_all();
	return job->id;
}

void ImageDecodeQueue::Cancel(uint32_t id) {
	{
		std::lock_guard<std::mutex> lock(state->mutex);
		auto at = state->jobs.find(id);
		if (at != state->jobs.end()) at->second->canceled.store(true);
	}
	state->changed.notify_all();
}

std::vector<ImageDecoded> ImageDecodeQueue::Take() {
	std::vector<ImageDecoded> results;
	std::lock_guard<std::mutex> lock(state->mutex);
	if (state->closing) return results;
	for (auto &entry : state->ready) {
		state->activeBytes -= entry.image.byteCount;
		if (!entry.job->canceled.load()) results.push_back(std::move(entry.image));
		state->jobs.erase(entry.job->id);
	}
	state->ready.clear();
	state->changed.notify_all();
	return results;
}

void ImageDecodeQueue::Close() {
	{
		std::lock_guard<std::mutex> lock(state->mutex);
		state->closing = true;
	}
	state->changed.notify_all();
}

#ifdef NEON_IMAGE_WORKER_TEST
ImageDecodeQueue::Stats ImageDecodeQueue::Inspect() {
	std::lock_guard<std::mutex> lock(state->mutex);
	return {state->workers, state->waitingForBytes, state->activeBytes};
}
#endif

// RNW ImageLoader getSize (ImageViewManagerModule.cpp:21-84) reads IWICBitmapSource::GetSize of frame 0 of the decoded stream.
ImageSize ImageHeaderSize(const char *uri) {
	std::vector<BYTE> data;
	ComPtr<IWICBitmapDecoder> decoder;
	std::string error;
	HRESULT hr = openDecoder(factory(), uri, &data, &decoder, &error);
	return frameSize(hr, decoder.Get(), error);
}

ImageSize ImageHeaderSizeOfFile(const std::wstring &path) {
	ComPtr<IWICBitmapDecoder> decoder;
	HRESULT hr = factory()->CreateDecoderFromFilename(path.c_str(), nullptr, GENERIC_READ, WICDecodeMetadataCacheOnDemand, &decoder);
	return frameSize(hr, decoder.Get(), "");
}

bool ImageIsNetwork(const char *uri) { return isNetwork(uri); }

uint32_t ImageFetch(const char *uri) {
	uint32_t id = imageRequestId();
	HANDLE thread = CreateThread(nullptr, 0, fetchWorker, new FetchJob{id, uri}, 0, nullptr);
	if (!thread) {
		fprintf(stderr, "neon windows bridge: CreateThread for an image download failed, error %lu\n", GetLastError());
		fflush(stderr);
		abort();
	}
	CloseHandle(thread);
	return id;
}

std::vector<ImageDownload> ImageTakeDownloads() {
	std::vector<ImageDownload> taken;
	std::lock_guard<std::mutex> lock(g_downloadsLock);
	taken.swap(g_downloads);
	return taken;
}

ImagePicture *ImagePicture::Waiting(uint32_t id) {
	auto at = g_waiting.find(id);
	return at == g_waiting.end() ? nullptr : at->second;
}

ImagePicture::~ImagePicture() { CancelFetch(); }

void ImagePicture::CancelFetch() {
	if (fetching) g_waiting.erase(fetching);
	fetching = 0;
}

void ImagePicture::Deliver(const ImageDownload &download) {
	fetching = 0;
	g_waiting.erase(download.id);
	paintDirty = true;
	if (!download.error.empty()) {
		failure = download.error;
		pending = kImageError;
		return;
	}
	ComPtr<IWICBitmapDecoder> decoder;
	HRESULT hr = factory()->CreateDecoderFromFilename(download.path.c_str(), nullptr, GENERIC_READ, WICDecodeMetadataCacheOnDemand, &decoder);
	if (FAILED(hr)) {
		failure = loadError("cannot decode image", hr);
		pending = kImageError;
		return;
	}
	Decode(decoder.Get());
}

void ImagePicture::Load(const char *newUri) {
	uri = newUri;
	CancelFetch();
	pixels.Reset();
	pixelsWide = pixelsHigh = 0;
	pending = kImageNone;
	failure.clear();
	paintDirty = true;
	if (uri.empty()) return;
	if (isNetwork(newUri)) {
		fetching = ImageFetch(newUri);
		g_waiting[fetching] = this;
		return;
	}
	std::vector<BYTE> data;
	ComPtr<IWICBitmapDecoder> decoder;
	if (FAILED(openDecoder(factory(), newUri, &data, &decoder, &failure))) {
		pending = kImageError;
		return;
	}
	Decode(decoder.Get());
}

void ImagePicture::Decode(IWICBitmapDecoder *decoder) {
#ifdef NEON_IMAGE_WORKER_TEST
	imageWorkerDecodeProbe();
#endif
	IWICImagingFactory *wic = factory();
	ComPtr<IWICBitmapFrameDecode> frame;
	ComPtr<IWICFormatConverter> converter;
	HRESULT hr = decoder->GetFrame(0, &frame);
	if (SUCCEEDED(hr)) hr = wic->CreateFormatConverter(&converter);
	if (SUCCEEDED(hr)) hr = converter->Initialize(frame.Get(), GUID_WICPixelFormat32bppPBGRA, WICBitmapDitherTypeNone, nullptr, 0.0, WICBitmapPaletteTypeCustom);
	if (SUCCEEDED(hr)) hr = wic->CreateBitmapFromSource(converter.Get(), WICBitmapCacheOnLoad, &pixels);
	if (SUCCEEDED(hr)) hr = pixels->GetSize(&pixelsWide, &pixelsHigh);
	if (FAILED(hr)) {
		pixels.Reset();
		failure = loadError("cannot decode image", hr);
		pending = kImageError;
		return;
	}
	pending = kImageLoad;
}

bool ImagePicture::SetProp(const char *name, const char *value) {
	if (!strcmp(name, "source")) {
		if (uri != value) Load(value);
	} else if (!strcmp(name, "resizeMode")) {
		Mode next;
		if (!strcmp(value, "cover")) next = kCover;
		else if (!strcmp(value, "contain")) next = kContain;
		else if (!strcmp(value, "stretch")) next = kStretch;
		else if (!strcmp(value, "center")) next = kCenter;
		else if (!strcmp(value, "repeat")) next = kRepeat;
		else refuse("Image resizeMode", value);
		mode = next;
		paintDirty = true;
	} else if (!strcmp(name, "blurRadius")) {
		blur = (float)atof(value);
		paintDirty = true;
	} else {
		return false;
	}
	return true;
}

void ImagePicture::SetBackground(Color color) {
	background = color;
	paintDirty = true;
}

ImageReport ImagePicture::TakeReport(std::string *error, float *width, float *height) {
	ImageReport report = pending;
	pending = kImageNone;
	*error = failure;
	*width = (float)pixelsWide;
	*height = (float)pixelsHigh;
	return report;
}

bool ImagePicture::NeedsDraw(int32_t pixelWidth, int32_t pixelHeight) const {
	return paintDirty || pixelWidth != drawnWidth || pixelHeight != drawnHeight;
}

// RNW ImageComponentView::DrawImage (:326-421) draws the WIC bitmap through D2D, and ensureDrawingSurface (:284-310)
// maps resizeMode to a stretch; here the same placement is a transform into the view's own surface.
void ImagePicture::Draw(ICompositionContext *context, IVisual *visual, int32_t pixelWidth, int32_t pixelHeight, float scale) {
	bool resized = pixelWidth != drawnWidth || pixelHeight != drawnHeight;
	drawnWidth = pixelWidth;
	drawnHeight = pixelHeight;
	paintDirty = false;
	if ((!pixels && background.a <= 0) || pixelWidth <= 0 || pixelHeight <= 0) {
		surface.reset();
		visual->Content(nullptr);
		return;
	}
	if (!surface || resized) {
		surface.reset(context->CreateDrawingSurface(pixelWidth, pixelHeight));
		visual->Content(surface.get());
	}
	ID2D1DeviceContext *dc = static_cast<ID2D1DeviceContext *>(surface->BeginDrawD2D(96.0f));
	ID2D1RenderTarget *target = dc;
	dc->Clear(D2D1::ColorF(background.r, background.g, background.b, background.a));
	if (!pixels) {
		surface->EndDraw();
		return;
	}
	ComPtr<ID2D1Bitmap> bitmap;
	must(target->CreateBitmapFromWicBitmap(pixels.Get(),
		D2D1::BitmapProperties(D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_PREMULTIPLIED), 96.0f, 96.0f), &bitmap), "CreateBitmapFromWicBitmap");
	float boxW = (float)pixelWidth, boxH = (float)pixelHeight;
	float imageW = (float)pixelsWide, imageH = (float)pixelsHigh;
	D2D1_MATRIX_3X2_F origin;
	dc->GetTransform(&origin);
	target->PushAxisAlignedClip(D2D1::RectF(0, 0, boxW, boxH), D2D1_ANTIALIAS_MODE_ALIASED);
	if (mode == kRepeat) {
		ComPtr<ID2D1BitmapBrush> brush;
		must(target->CreateBitmapBrush(bitmap.Get(), D2D1::BitmapBrushProperties(D2D1_EXTEND_MODE_WRAP, D2D1_EXTEND_MODE_WRAP),
			D2D1::BrushProperties(1.0f, D2D1::Matrix3x2F::Scale(scale, scale)), &brush), "CreateBitmapBrush");
		target->FillRectangle(D2D1::RectF(0, 0, boxW, boxH), brush.Get());
	} else {
		float scaleX = scale, scaleY = scale;
		if (mode == kStretch) {
			scaleX = boxW / imageW;
			scaleY = boxH / imageH;
		} else if (mode != kCenter) {
			float fit = mode == kCover ? std::max(boxW / imageW, boxH / imageH) : std::min(boxW / imageW, boxH / imageH);
			scaleX = scaleY = fit;
		}
		dc->SetTransform(D2D1::Matrix3x2F::Scale(scaleX, scaleY) * D2D1::Matrix3x2F::Translation((boxW - imageW * scaleX) / 2, (boxH - imageH * scaleY) / 2) * origin);
		ComPtr<ID2D1Image> image = bitmap;
		ComPtr<ID2D1Effect> blurred;
		if (blur > 0) {
			must(dc->CreateEffect(CLSID_D2D1GaussianBlur, &blurred), "CreateEffect(GaussianBlur)");
			blurred->SetInput(0, bitmap.Get());
			must(blurred->SetValue(D2D1_GAUSSIANBLUR_PROP_STANDARD_DEVIATION, blur), "SetValue(StandardDeviation)");
			must(blurred->SetValue(D2D1_GAUSSIANBLUR_PROP_BORDER_MODE, D2D1_BORDER_MODE_HARD), "SetValue(BorderMode)");
			blurred->GetOutput(image.ReleaseAndGetAddressOf());
		}
		dc->DrawImage(image.Get(), nullptr, nullptr, D2D1_INTERPOLATION_MODE_LINEAR, D2D1_COMPOSITE_MODE_SOURCE_OVER);
		dc->SetTransform(origin);
	}
	target->PopAxisAlignedClip();
	surface->EndDraw();
}
