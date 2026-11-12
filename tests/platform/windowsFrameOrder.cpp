#include <d3d11.h>
#include <dcomp.h>
#include <d2d1_1.h>
#include <wrl/client.h>
extern "C" {
#include "../../src/platform/native/bridge.h"
}
#include "../../src/platform/windows/handoff.h"
#include "windowsFrameOrder.h"

using Microsoft::WRL::ComPtr;
static ComPtr<ID3D11Device> gpu;
static ComPtr<ID2D1Factory1> factory;
static ComPtr<ID2D1Device> drawingDevice;
static ComPtr<IDCompositionDesktopDevice> device;
static ComPtr<IDCompositionVisual2> root;
static int order, requests, loopRequests;
static bool initialized;
static const char *setupStage;

extern "C" void ionWakeLoop(void) {}

static void requested(void) { requests++; }
static void frame(void) { order = order * 10 + 1; }
static void loop(void) {
	order = order * 10 + 2;
	if (loopRequests) niRequestFrame();
}

int32_t nfwSetup(void) {
	if (initialized) return 0;
	setupStage = "D3D11CreateDevice WARP";
	HRESULT hr = D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_WARP, nullptr,
		D3D11_CREATE_DEVICE_BGRA_SUPPORT, nullptr, 0, D3D11_SDK_VERSION,
		&gpu, nullptr, nullptr);
	if (FAILED(hr)) return hr;
	ComPtr<IDXGIDevice> dxgi;
	setupStage = "IDXGIDevice";
	hr = gpu.As(&dxgi);
	if (FAILED(hr)) return hr;
	setupStage = "D2D1CreateFactory";
	hr = D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED,
		__uuidof(ID2D1Factory1), nullptr, (void **)factory.GetAddressOf());
	if (FAILED(hr)) return hr;
	setupStage = "ID2D1Factory1 CreateDevice";
	hr = factory->CreateDevice(dxgi.Get(), &drawingDevice);
	if (FAILED(hr)) return hr;
	setupStage = "DCompositionCreateDevice2";
	hr = DCompositionCreateDevice2(drawingDevice.Get(), IID_PPV_ARGS(&device));
	if (FAILED(hr)) return hr;
	setupStage = "CreateVisual";
	hr = device->CreateVisual(&root);
	if (FAILED(hr)) return hr;
	niwAttach(device.Get(), root.Get(), 96, 200, 100);
	initialized = true;
	return 0;
}

int32_t nfwOrder(int32_t requestFromLoop) {
	order = requests = 0;
	loopRequests = requestFromLoop;
	niwSetFrameRequester(msClosure{(void *)requested, nullptr});
	niSetFrameHandler(msClosure{(void *)frame, nullptr});
	niSetLoopHandler(msClosure{(void *)loop, nullptr});
	niRequestFrame();
	niwFrame(1234);
	niSetFrameHandler(msClosure{});
	niSetLoopHandler(msClosure{});
	return order;
}

int32_t nfwRequests(void) { return requests; }
const char *nfwStage(void) { return setupStage; }
