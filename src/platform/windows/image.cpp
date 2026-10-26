#include <windows.h>
#include <d2d1_1.h>
#include <d2d1effects.h>
#include <wincodec.h>
#include <wrl/client.h>
#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>
#include "image.h"
#include "must.h"

using Microsoft::WRL::ComPtr;

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
HRESULT openDecoder(const char *uri, std::vector<BYTE> *data, ComPtr<IWICBitmapDecoder> *decoder, std::string *error) {
	IWICImagingFactory *wic = factory();
	if (startsWith(uri, "file://")) {
		std::string path = percentDecoded(uri + 7);
		if (path.size() > 2 && path[0] == '/' && path[2] == ':') path.erase(0, 1);
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
		ComPtr<IWICStream> stream;
		HRESULT hr = wic->CreateStream(&stream);
		if (SUCCEEDED(hr)) hr = stream->InitializeFromMemory(data->data(), (DWORD)data->size());
		if (SUCCEEDED(hr)) hr = wic->CreateDecoderFromStream(stream.Get(), nullptr, WICDecodeMetadataCacheOnDemand, decoder->GetAddressOf());
		if (FAILED(hr)) *error = loadError("cannot decode image", hr);
		return hr;
	}
	*error = startsWith(uri, "http://") || startsWith(uri, "https://") ? "network images are not implemented on Windows yet" : "unsupported URI scheme";
	return E_NOTIMPL;
}

}

void ImagePicture::Load(const char *newUri) {
	uri = newUri;
	pixels.Reset();
	pixelsWide = pixelsHigh = 0;
	pending = kImageNone;
	failure.clear();
	paintDirty = true;
	if (uri.empty()) return;
	std::vector<BYTE> data;
	ComPtr<IWICBitmapDecoder> decoder;
	if (FAILED(openDecoder(newUri, &data, &decoder, &failure))) {
		pending = kImageError;
		return;
	}
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
