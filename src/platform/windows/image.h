#pragma once
#include <wincodec.h>
#include <wrl/client.h>
#include <cstdint>
#include <memory>
#include <string>
#include "composition.h"

enum ImageReport { kImageNone, kImageLoad, kImageError };

// An Image decodes its source once, through WIC, into a premultiplied BGRA bitmap and draws it into the view's
// surface at one device-independent pixel per image pixel, as the macOS host does. A source is a data: URI with
// base64 content or a file: URI; the outcome waits for TakeReport, which the frame sends as onLoad or onError.
class ImagePicture {
public:
	bool SetProp(const char *name, const char *value);
	void SetBackground(Color color);
	ImageReport TakeReport(std::string *error, float *width, float *height);
	void Invalidate() { paintDirty = true; }
	bool NeedsDraw(int32_t pixelWidth, int32_t pixelHeight) const;
	void Draw(ICompositionContext *context, IVisual *visual, int32_t pixelWidth, int32_t pixelHeight, float scale);

private:
	enum Mode { kCover, kContain, kStretch, kCenter, kRepeat };

	void Load(const char *uri);

	std::string uri;
	Mode mode = kCover;
	float blur = 0;
	Color background = {0, 0, 0, 0};
	Microsoft::WRL::ComPtr<IWICBitmap> pixels;
	uint32_t pixelsWide = 0, pixelsHigh = 0;
	ImageReport pending = kImageNone;
	std::string failure;
	std::unique_ptr<IDrawingSurface> surface;
	int32_t drawnWidth = -1, drawnHeight = -1;
	bool paintDirty = true;
};
