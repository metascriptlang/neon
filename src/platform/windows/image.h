#pragma once
#include <wincodec.h>
#include <wrl/client.h>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>
#include "composition.h"

enum ImageReport { kImageNone, kImageLoad, kImageError };

struct ImageSize {
	uint32_t width = 0, height = 0;
	std::string error;
};

// A finished download: the URL-cache file of the source, or the error that stopped it.
struct ImageDownload {
	uint32_t id = 0;
	std::wstring path;
	std::string error;
};

// Frame 0's pixel size from the decoder header, with no pixel decode. A file: or data: URI only; on the host thread.
ImageSize ImageHeaderSize(const char *uri);
ImageSize ImageHeaderSizeOfFile(const std::wstring &path);
bool ImageIsNetwork(const char *uri);
// Starts a download of an http(s) URI into the URL cache on a worker thread and returns its id. The worker calls
// ionWakeLoop when it is done; the host thread then takes the results with ImageTakeDownloads.
uint32_t ImageFetch(const char *uri);
std::vector<ImageDownload> ImageTakeDownloads();

// An Image decodes its source once, through WIC, into a premultiplied BGRA bitmap and draws it into the view's
// surface at one device-independent pixel per image pixel, as the macOS host does. A source is a data: URI with
// base64 content, a file: URI or an http(s) URI downloaded into the URL cache; the outcome waits for TakeReport, which the frame sends as onLoad or onError.
class ImagePicture {
public:
	~ImagePicture();
	void *owner = nullptr;
	static ImagePicture *Waiting(uint32_t id);
	void Deliver(const ImageDownload &download);
	bool SetProp(const char *name, const char *value);
	void SetBackground(Color color);
	ImageReport TakeReport(std::string *error, float *width, float *height);
	void Invalidate() { paintDirty = true; }
	bool NeedsDraw(int32_t pixelWidth, int32_t pixelHeight) const;
	void Draw(ICompositionContext *context, IVisual *visual, int32_t pixelWidth, int32_t pixelHeight, float scale);

private:
	enum Mode { kCover, kContain, kStretch, kCenter, kRepeat };

	void Load(const char *uri);
	void Decode(IWICBitmapDecoder *decoder);
	void CancelFetch();

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
	uint32_t fetching = 0;
};
