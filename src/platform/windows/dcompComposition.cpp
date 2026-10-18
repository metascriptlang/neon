#include <windows.h>
#include <d2d1_1.h>
#include <dcomp.h>
#include <dxgi1_2.h>
#include <wrl/client.h>
#include <algorithm>
#include <memory>
#include <vector>
#include "dcompComposition.h"
#include "must.h"

using Microsoft::WRL::ComPtr;

namespace {

class DCompDrawingSurface : public IDrawingSurface {
public:
	explicit DCompDrawingSurface(ComPtr<IDCompositionSurface> surface) : surface(surface) {}

	void *BeginDrawD2D(float dpi) override {
		if (dc) must(E_UNEXPECTED, "BeginDraw during a draw");
		POINT origin = {};
		must(surface->BeginDraw(nullptr, __uuidof(ID2D1DeviceContext), (void **)dc.GetAddressOf(), &origin), "BeginDraw");
		float unit = 96.0f / dpi;
		dc->SetDpi(dpi, dpi);
		dc->SetTransform(D2D1::Matrix3x2F::Translation(origin.x * unit, origin.y * unit));
		return dc.Get();
	}

	void EndDraw() override {
		if (!dc) must(E_UNEXPECTED, "EndDraw without BeginDraw");
		must(surface->EndDraw(), "EndDraw");
		dc.Reset();
	}

	ComPtr<IDCompositionSurface> surface;

private:
	ComPtr<ID2D1DeviceContext> dc;
};

class DCompContext;

class DCompVisual : public IVisual {
public:
	DCompVisual(DCompContext *context, ComPtr<IDCompositionVisual2> visual);
	~DCompVisual() override;
	void InsertAt(IVisual *visual, int32_t index) override;
	void Remove(IVisual *visual) override;
	void Opacity(float opacity) override;
	void TransformMatrix(const float m[6]) override;
	void Size(float width, float height) override;
	void Offset(float x, float y) override;
	void CornerRadius(float radius) override;
	void ClipsChildren(bool clips) override;
	void Brush(Color color) override;
	void Content(IDrawingSurface *surface) override;
	void Sync();

private:
	void markDirty();

	DCompContext *context;
	ComPtr<IDCompositionVisual2> visual;
	ComPtr<IDCompositionEffectGroup> effect;
	ComPtr<IDCompositionRectangleClip> clip;
	std::vector<DCompVisual *> children;
	float width = 0, height = 0, radius = 0;
	Color color = {0, 0, 0, 0};
	bool clipsChildren = false;
	bool contentDirty = false;
	bool pending = false;
};

class DCompContext : public ICompositionContext {
public:
	explicit DCompContext(ComPtr<IDCompositionDevice2> device) : device(device) {}

	IVisual *CreateSpriteVisual() override {
		ComPtr<IDCompositionVisual2> visual;
		must(device->CreateVisual(&visual), "CreateVisual");
		return new DCompVisual(this, visual);
	}

	IDrawingSurface *CreateDrawingSurface(int32_t pixelWidth, int32_t pixelHeight) override {
		ComPtr<IDCompositionSurface> surface;
		must(device->CreateSurface((UINT)pixelWidth, (UINT)pixelHeight, DXGI_FORMAT_B8G8R8A8_UNORM,
			DXGI_ALPHA_MODE_PREMULTIPLIED, &surface), "CreateSurface");
		return new DCompDrawingSurface(surface);
	}

	void Commit() override {
		std::vector<DCompVisual *> due;
		due.swap(pendingSync);
		for (DCompVisual *visual : due) visual->Sync();
		must(device->Commit(), "Commit");
	}

	ComPtr<IDCompositionDevice2> device;
	std::vector<DCompVisual *> pendingSync;
};

DCompVisual::DCompVisual(DCompContext *context, ComPtr<IDCompositionVisual2> visual) : context(context), visual(visual) {}

DCompVisual::~DCompVisual() {
	if (!pending) return;
	auto &list = context->pendingSync;
	list.erase(std::remove(list.begin(), list.end(), this), list.end());
}

void DCompVisual::markDirty() {
	if (pending) return;
	pending = true;
	context->pendingSync.push_back(this);
}

void DCompVisual::InsertAt(IVisual *child, int32_t index) {
	DCompVisual *added = static_cast<DCompVisual *>(child);
	size_t at = index < 0 || (size_t)index > children.size() ? children.size() : (size_t)index;
	if (at == children.size()) {
		must(visual->AddVisual(added->visual.Get(), FALSE, nullptr), "AddVisual");
	} else {
		must(visual->AddVisual(added->visual.Get(), FALSE, children[at]->visual.Get()), "AddVisual");
	}
	children.insert(children.begin() + at, added);
}

void DCompVisual::Remove(IVisual *child) {
	DCompVisual *removed = static_cast<DCompVisual *>(child);
	must(visual->RemoveVisual(removed->visual.Get()), "RemoveVisual");
	children.erase(std::remove(children.begin(), children.end(), removed), children.end());
}

void DCompVisual::Opacity(float opacity) {
	if (!effect) {
		must(context->device->CreateEffectGroup(&effect), "CreateEffectGroup");
		must(visual->SetEffect(effect.Get()), "SetEffect");
	}
	must(effect->SetOpacity(opacity), "SetOpacity");
}

void DCompVisual::TransformMatrix(const float m[6]) {
	D2D1_MATRIX_3X2_F matrix = {m[0], m[1], m[2], m[3], m[4], m[5]};
	must(visual->SetTransform(matrix), "SetTransform");
}

void DCompVisual::Size(float w, float h) {
	if (w == width && h == height) return;
	width = w;
	height = h;
	if (color.a > 0) contentDirty = true;
	markDirty();
}

void DCompVisual::Offset(float x, float y) {
	must(visual->SetOffsetX(x), "SetOffsetX");
	must(visual->SetOffsetY(y), "SetOffsetY");
}

void DCompVisual::CornerRadius(float r) {
	if (r == radius) return;
	radius = r;
	markDirty();
}

void DCompVisual::ClipsChildren(bool clips) {
	if (clips == clipsChildren) return;
	clipsChildren = clips;
	markDirty();
}

void DCompVisual::Brush(Color c) {
	if (c.r == color.r && c.g == color.g && c.b == color.b && c.a == color.a) return;
	color = c;
	contentDirty = true;
	markDirty();
}

void DCompVisual::Content(IDrawingSurface *surface) {
	color = {0, 0, 0, 0};
	contentDirty = false;
	must(visual->SetContent(surface ? static_cast<DCompDrawingSurface *>(surface)->surface.Get() : nullptr), "SetContent");
}

void DCompVisual::Sync() {
	pending = false;
	if (contentDirty) {
		contentDirty = false;
		if (color.a > 0 && width > 0 && height > 0) {
			std::unique_ptr<IDrawingSurface> surface(context->CreateDrawingSurface((int32_t)width, (int32_t)height));
			ID2D1DeviceContext *dc = static_cast<ID2D1DeviceContext *>(surface->BeginDrawD2D(96.0f));
			dc->Clear(D2D1::ColorF(color.r, color.g, color.b, color.a));
			surface->EndDraw();
			must(visual->SetContent(static_cast<DCompDrawingSurface *>(surface.get())->surface.Get()), "SetContent");
		} else {
			must(visual->SetContent(nullptr), "SetContent");
		}
	}
	if ((radius > 0 || clipsChildren) && width > 0 && height > 0) {
		if (!clip) must(context->device->CreateRectangleClip(&clip), "CreateRectangleClip");
		float r = std::min(radius, std::min(width, height) / 2);
		clip->SetLeft(0.0f);
		clip->SetTop(0.0f);
		clip->SetRight(width);
		clip->SetBottom(height);
		clip->SetTopLeftRadiusX(r);
		clip->SetTopLeftRadiusY(r);
		clip->SetTopRightRadiusX(r);
		clip->SetTopRightRadiusY(r);
		clip->SetBottomLeftRadiusX(r);
		clip->SetBottomLeftRadiusY(r);
		clip->SetBottomRightRadiusX(r);
		clip->SetBottomRightRadiusY(r);
		must(visual->SetClip(clip.Get()), "SetClip");
	} else if (clip) {
		must(visual->SetClip(static_cast<IDCompositionClip *>(nullptr)), "SetClip");
		clip.Reset();
	}
}

}

ICompositionContext *CreateDCompContext(void *dcompDevice2) {
	ComPtr<IDCompositionDevice2> device;
	must(static_cast<IUnknown *>(dcompDevice2)->QueryInterface(IID_PPV_ARGS(&device)), "IDCompositionDevice2");
	return new DCompContext(device);
}

IVisual *AdoptDCompVisual(ICompositionContext *context, void *visual2) {
	ComPtr<IDCompositionVisual2> visual;
	must(static_cast<IUnknown *>(visual2)->QueryInterface(IID_PPV_ARGS(&visual)), "IDCompositionVisual2");
	return new DCompVisual(static_cast<DCompContext *>(context), visual);
}
