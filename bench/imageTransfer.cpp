#include <windows.h>
#include <objidl.h>
#include <combaseapi.h>
#include <wincodec.h>
#include <d3d11.h>
#include <d2d1_1.h>
#include <wrl/client.h>
#include <algorithm>
#include <cstring>
#include <cstdio>
#include <cstdint>
#include <stdexcept>
#include <string>
#include <vector>

using Microsoft::WRL::ComPtr;

static void check(HRESULT result, const char *operation) {
	if (SUCCEEDED(result)) return;
	char message[160];
	snprintf(message, sizeof message, "%s failed: 0x%08lx",
		operation, (unsigned long)result);
	throw std::runtime_error(message);
}

static double now() {
	LARGE_INTEGER counter, frequency;
	QueryPerformanceFrequency(&frequency);
	QueryPerformanceCounter(&counter);
	return counter.QuadPart * 1000.0 / (double)frequency.QuadPart;
}

static void gpuProfile(IWICBitmap *pixels, const std::vector<BYTE> &bytes,
	UINT width, UINT height, bool corrupt) {
	DWORD_PTR allowed = 0, system = 0;
	if (!GetProcessAffinityMask(GetCurrentProcess(), &allowed, &system) ||
		(allowed & 3) != 3 || !SetProcessAffinityMask(GetCurrentProcess(), 3)) {
		throw std::runtime_error("GPU probe requires first two CPUs available");
	}
	ComPtr<ID3D11Device> gpu;
	check(D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_WARP, nullptr,
		D3D11_CREATE_DEVICE_BGRA_SUPPORT, nullptr, 0, D3D11_SDK_VERSION,
		&gpu, nullptr, nullptr), "WARP device");
	ComPtr<IDXGIDevice> dxgi;
	check(gpu.As(&dxgi), "DXGI device");
	ComPtr<ID2D1Factory1> factory;
	check(D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED,
		__uuidof(ID2D1Factory1), nullptr, (void **)factory.GetAddressOf()),
		"D2D factory");
	ComPtr<ID2D1Device> drawing;
	check(factory->CreateDevice(dxgi.Get(), &drawing), "D2D device");
	ComPtr<ID2D1DeviceContext> dc;
	check(drawing->CreateDeviceContext(D2D1_DEVICE_CONTEXT_OPTIONS_NONE,
		&dc), "D2D context");
	auto size = D2D1::SizeU(width, height);
	auto format = D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM,
		D2D1_ALPHA_MODE_PREMULTIPLIED);
	auto targetProps = D2D1::BitmapProperties1(
		D2D1_BITMAP_OPTIONS_TARGET | D2D1_BITMAP_OPTIONS_CANNOT_DRAW,
		format, 96, 96);
	auto readProps = D2D1::BitmapProperties1(
		D2D1_BITMAP_OPTIONS_CPU_READ | D2D1_BITMAP_OPTIONS_CANNOT_DRAW,
		format, 96, 96);
	ComPtr<ID2D1Bitmap1> surface, readback;
	check(dc->CreateBitmap(size, nullptr, 0, &targetProps, &surface),
		"owned target");
	check(dc->CreateBitmap(size, nullptr, 0, &readProps, &readback),
		"owned readback");
	dc->SetTarget(surface.Get());
	dc->SetDpi(96, 96);
	std::vector<BYTE> changed;
	const BYTE *raw = bytes.data();
	if (corrupt) {
		changed = bytes;
		changed[0] = changed[0] == 0 ? 255 : 0;
		changed[3] = 255;
		raw = changed.data();
	}
	auto bitmap = [&](bool wic) {
		ComPtr<ID2D1Bitmap> image;
		auto props = D2D1::BitmapProperties(format, 96, 96);
		ID2D1RenderTarget *target = dc.Get();
		if (wic) {
			check(target->CreateBitmapFromWicBitmap(pixels, &props, &image),
				"CreateBitmapFromWicBitmap");
		} else {
			check(target->CreateBitmap(size, raw, width * 4, &props, &image),
				"CreateBitmap raw");
		}
		return image;
	};
	auto render = [&](ID2D1Bitmap *image) {
		dc->BeginDraw();
		dc->Clear(D2D1::ColorF(0, 0, 0, 0));
		dc->DrawImage(image, nullptr, nullptr, D2D1_INTERPOLATION_MODE_LINEAR,
			D2D1_COMPOSITE_MODE_SOURCE_OVER);
		check(dc->EndDraw(), "owned draw");
		check(readback->CopyFromBitmap(nullptr, surface.Get(), nullptr),
			"owned readback copy");
		std::vector<BYTE> result(bytes.size());
		D2D1_MAPPED_RECT mapped;
		check(readback->Map(D2D1_MAP_OPTIONS_READ, &mapped), "owned map");
		if (mapped.pitch < width * 4) {
			check(readback->Unmap(), "short-pitch unmap");
			throw std::runtime_error("owned readback pitch too short");
		}
		for (UINT row = 0; row < height; row++) {
			memcpy(result.data() + (size_t)row * width * 4,
				mapped.bits + (size_t)row * mapped.pitch, width * 4);
		}
		check(readback->Unmap(), "owned unmap");
		return result;
	};
	auto reference = render(bitmap(false).Get());
	if (std::all_of(reference.begin(), reference.end(),
		[](BYTE byte) { return byte == 0; })) {
		throw std::runtime_error("blank GPU reference");
	}
	printf("image-gpu-setup WARP affinity=3 nonblank=1 corrupt=%d\n", corrupt);
	if (render(bitmap(true).Get()) != reference) {
		throw std::runtime_error("GPU pixels differ from raw reference");
	}
	for (int round = 0; round < 5; round++) {
		for (int step = 0; step < 2; step++) {
			bool wic = (round + step) % 2 == 0;
			double started = now();
			auto image = bitmap(wic);
			double upload = now() - started;
			started = now();
			auto actual = render(image.Get());
			double collected = now() - started;
			if (actual != reference) {
				throw std::runtime_error("GPU pixels differ from raw reference");
			}
			printf("image-gpu %u %u %d %s upload-ms=%.6f "
				"draw-readback-copy-ms=%.6f equal=1\n", width, height, round,
				wic ? "wic-proxy" : "raw-bytes", upload, collected);
		}
	}
}

static void waitFor(HANDLE handle) {
	if (WaitForSingleObject(handle, INFINITE) == WAIT_OBJECT_0) return;
	fprintf(stderr, "image-transfer: wait failed\n");
	ExitProcess(2);
}

struct MtaUsage {
	CO_MTA_USAGE_COOKIE cookie = nullptr;

	~MtaUsage() {
		if (!cookie) return;
		HRESULT result = CoDecrementMTAUsage(cookie);
		if (SUCCEEDED(result)) return;
		fprintf(stderr, "image-transfer: CoDecrementMTAUsage 0x%08lx\n",
			(unsigned long)result);
		ExitProcess(2);
	}
};

struct Job {
	std::wstring path;
	ComPtr<IStream> stream;
	std::vector<BYTE> expected;
	UINT width = 0, height = 0;
	HRESULT agile = E_NOINTERFACE;
	std::string error;
	bool keepMta = false;
	HANDLE prepared = nullptr, release = nullptr, worker = nullptr;

	~Job() {
		if (release) SetEvent(release);
		if (worker) {
			waitFor(worker);
			CloseHandle(worker);
		}
		if (stream) CoReleaseMarshalData(stream.Get());
		if (prepared) CloseHandle(prepared);
		if (release) CloseHandle(release);
	}
};

static DWORD WINAPI decode(void *argument) {
	Job &job = *static_cast<Job *>(argument);
	HRESULT initialized = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
	if (FAILED(initialized)) {
		job.error = "worker CoInitializeEx failed";
		SetEvent(job.prepared);
		return 2;
	}
	try {
		ComPtr<IWICImagingFactory> factory;
		check(CoCreateInstance(CLSID_WICImagingFactory, nullptr,
			CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&factory)), "factory");
		ComPtr<IWICBitmapDecoder> decoder;
		check(factory->CreateDecoderFromFilename(job.path.c_str(), nullptr,
			GENERIC_READ, WICDecodeMetadataCacheOnDemand, &decoder), "decoder");
		ComPtr<IWICBitmapFrameDecode> frame;
		check(decoder->GetFrame(0, &frame), "frame");
		ComPtr<IWICFormatConverter> converter;
		check(factory->CreateFormatConverter(&converter), "converter");
		check(converter->Initialize(frame.Get(), GUID_WICPixelFormat32bppPBGRA,
			WICBitmapDitherTypeNone, nullptr, 0, WICBitmapPaletteTypeCustom),
			"convert PBGRA");
		ComPtr<IWICBitmap> pixels;
		check(factory->CreateBitmapFromSource(converter.Get(),
			WICBitmapCacheOnLoad, &pixels), "realize pixels");
		check(pixels->GetSize(&job.width, &job.height), "worker size");
		uint64_t bytes = (uint64_t)job.width * job.height * 4;
		if (!job.width || job.width > 16384 || !job.height ||
			job.height > 16384 || bytes > 256 * 1024 * 1024) {
			throw std::runtime_error("bitmap exceeds diagnostic limit256MiB");
		}
		job.expected.resize((size_t)bytes);
		check(pixels->CopyPixels(nullptr, job.width * 4, (UINT)bytes,
			job.expected.data()), "worker pixels");
		ComPtr<IAgileObject> agile;
		job.agile = pixels.As(&agile);
		check(CoMarshalInterThreadInterfaceInStream(__uuidof(IWICBitmap),
			pixels.Get(), &job.stream), "marshal bitmap");
	} catch (const std::exception &error) {
		job.error = error.what();
	}
	SetEvent(job.prepared);
	if (job.keepMta) waitFor(job.release);
	CoUninitialize();
	return job.error.empty() ? 0 : 2;
}

int main(int argc, char **argv) {
	bool keepMta = argc == 3 && std::string(argv[2]) == "--keep-mta";
	bool corrupt = argc == 3 && std::string(argv[2]) == "--warp-corrupt";
	bool warp = corrupt || (argc == 3 && std::string(argv[2]) == "--warp");
	bool mtaUsage = warp || (argc == 3 && std::string(argv[2]) == "--mta-usage");
	if (argc != 2 && !keepMta && !mtaUsage) {
		fprintf(stderr, "usage: image-transfer native-path "
			"[--keep-mta|--mta-usage|--warp|--warp-corrupt]\n");
		return 2;
	}
	HRESULT initialized = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
	if (FAILED(initialized)) {
		fprintf(stderr, "image-transfer: main STA initialization failed\n");
		return 2;
	}
	int result = 0;
	try {
		MtaUsage usage;
		if (mtaUsage) {
			check(CoIncrementMTAUsage(&usage.cookie), "CoIncrementMTAUsage");
		}
		APTTYPE apartment;
		APTTYPEQUALIFIER qualifier;
		check(CoGetApartmentType(&apartment, &qualifier), "main apartment");
		if (apartment != APTTYPE_STA && apartment != APTTYPE_MAINSTA) {
			throw std::runtime_error("main no longer STA");
		}
		Job job;
		job.keepMta = keepMta;
		job.prepared = CreateEventW(nullptr, TRUE, FALSE, nullptr);
		job.release = CreateEventW(nullptr, TRUE, FALSE, nullptr);
		if (!job.prepared || !job.release) {
			throw std::runtime_error("CreateEvent failed");
		}
		int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
			argv[1], -1, nullptr, 0);
		if (!count) throw std::runtime_error("invalid UTF-8 path");
		job.path.resize((size_t)count);
		MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
			argv[1], -1, job.path.data(), count);
		job.worker = CreateThread(nullptr, 0, decode, &job, 0, nullptr);
		if (!job.worker) throw std::runtime_error("CreateThread failed");
		waitFor(keepMta ? job.prepared : job.worker);
		if (!job.error.empty()) throw std::runtime_error(job.error);
		fprintf(stderr, "image-transfer-state keep-mta=%d mta-usage=%d "
			"main-sta=1 agile=0x%08lx\n", keepMta, mtaUsage,
			(unsigned long)job.agile);
		double started = now();
		ComPtr<IWICBitmap> pixels;
		check(CoGetInterfaceAndReleaseStream(job.stream.Detach(),
			__uuidof(IWICBitmap), &pixels), "unmarshal bitmap");
		UINT width = 0, height = 0;
		check(pixels->GetSize(&width, &height), "main size");
		double adopted = now() - started;
		if (width != job.width || height != job.height) {
			throw std::runtime_error("bitmap dimensions changed across STA");
		}
		std::vector<BYTE> actual;
		if (warp) {
			gpuProfile(pixels.Get(), job.expected, width, height, corrupt);
		} else {
			actual.resize(job.expected.size());
			check(pixels->CopyPixels(nullptr, width * 4, (UINT)actual.size(),
				actual.data()), "main pixels");
			if (actual != job.expected) {
				throw std::runtime_error("bitmap pixels changed across STA");
			}
		}
		printf("image-transfer %u %u %zu agile=0x%08lx adopt-ms=%.6f "
			"mta-usage=%d worker-exited=%d pixels-equal=1\n", width, height,
			job.expected.size(), (unsigned long)job.agile, adopted,
			mtaUsage, !keepMta);
		if (keepMta) {
			SetEvent(job.release);
			waitFor(job.worker);
			HRESULT after = pixels->GetSize(&width, &height);
			if (SUCCEEDED(after)) {
				actual.assign(actual.size(), 0);
				check(pixels->CopyPixels(nullptr, width * 4,
					(UINT)actual.size(), actual.data()), "pixels after exit");
				if (actual != job.expected) {
					throw std::runtime_error("pixels changed after exit");
				}
			} else if (after != RPC_E_DISCONNECTED) {
				check(after, "unexpected error after worker exit");
			}
			printf("image-transfer-after-exit size-hr=0x%08lx\n",
				(unsigned long)after);
		}
	} catch (const std::exception &error) {
		fprintf(stderr, "image-transfer: %s\n", error.what());
		result = 2;
	}
	CoUninitialize();
	return result;
}
