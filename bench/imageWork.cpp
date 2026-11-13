#include <windows.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include "../src/platform/windows/image.h"

extern "C" void ionWakeLoop(void) {
	fprintf(stderr, "image-work: unexpected network wake\n");
	abort();
}

static uint32_t dimension(const char *text) {
	char *end = nullptr;
	unsigned long value = strtoul(text, &end, 10);
	if (end == text || *end || value == 0 || value > 16384) {
		fprintf(stderr, "image-work: invalid dimension %s\n", text);
		exit(2);
	}
	return (uint32_t)value;
}

int main(int argc, char **argv) {
	if (argc != 4 || strncmp(argv[1], "file://", 7)) {
		fprintf(stderr, "usage: image-work file://path width height\n");
		return 2;
	}
	uint32_t width = dimension(argv[2]);
	uint32_t height = dimension(argv[3]);
	LARGE_INTEGER frequency;
	if (!QueryPerformanceFrequency(&frequency)) {
		fprintf(stderr, "image-work: no performance counter\n");
		return 2;
	}
	ImageSize header = ImageHeaderSize(argv[1]);
	if (!header.error.empty() || header.width != width || header.height != height) {
		fprintf(stderr, "image-work: header %ux%u: %s\n",
			header.width, header.height, header.error.c_str());
		return 2;
	}
	for (int round = 0; round < 5; round++) {
		LARGE_INTEGER start, end;
		QueryPerformanceCounter(&start);
		{
			ImagePicture picture;
			if (!picture.SetProp("source", argv[1])) {
				fprintf(stderr, "image-work: source not accepted\n");
				return 2;
			}
			std::string error;
			float reportedWidth = 0, reportedHeight = 0;
			ImageReport report = picture.TakeReport(
				&error, &reportedWidth, &reportedHeight);
			if (report != kImageLoad || reportedWidth != width ||
				reportedHeight != height || !error.empty()) {
				fprintf(stderr, "image-work: load report %d %.0fx%.0f: %s\n",
					(int)report, reportedWidth, reportedHeight, error.c_str());
				return 2;
			}
		}
		QueryPerformanceCounter(&end);
		double elapsed = (end.QuadPart - start.QuadPart) * 1000.0 /
			(double)frequency.QuadPart;
		printf("image-work load-decode-release %u %u %d %.6f\n",
			width, height, round, elapsed);
	}
	return 0;
}
