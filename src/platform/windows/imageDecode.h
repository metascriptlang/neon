#pragma once
#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

size_t ImageDecodeByteCount(uint32_t width, uint32_t height);

struct ImageDecoded {
	uint32_t id = 0, width = 0, height = 0;
	size_t byteCount = 0;
	std::unique_ptr<uint8_t[]> pixels;
	std::string error;
};

class ImageDecodeQueue {
public:
	explicit ImageDecodeQueue(void (*postWake)(void));
	~ImageDecodeQueue();
	ImageDecodeQueue(const ImageDecodeQueue &) = delete;
	ImageDecodeQueue &operator=(const ImageDecodeQueue &) = delete;
	uint32_t Submit(const char *uri);
	void Cancel(uint32_t id);
	std::vector<ImageDecoded> Take();
	void Close();
#ifdef NEON_IMAGE_WORKER_TEST
	struct Stats { uint32_t workers; size_t waitingForBytes, reservedBytes; };
	Stats Inspect();
#endif

private:
	struct State;
	std::shared_ptr<State> state;
};
