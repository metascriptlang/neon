#include <windows.h>
#include <objidl.h>
#include <combaseapi.h>
#include <wincodec.h>
#include <wrl/client.h>
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
	bool mtaUsage = argc == 3 && std::string(argv[2]) == "--mta-usage";
	if (argc != 2 && !keepMta && !mtaUsage) {
		fprintf(stderr,
			"usage: image-transfer native-path [--keep-mta|--mta-usage]\n");
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
		std::vector<BYTE> actual(job.expected.size());
		check(pixels->CopyPixels(nullptr, width * 4, (UINT)actual.size(),
			actual.data()), "main pixels");
		if (actual != job.expected) {
			throw std::runtime_error("bitmap pixels changed across STA");
		}
		printf("image-transfer %u %u %zu agile=0x%08lx adopt-ms=%.6f "
			"mta-usage=%d worker-exited=%d pixels-equal=1\n", width, height,
			actual.size(), (unsigned long)job.agile, adopted, mtaUsage, !keepMta);
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
