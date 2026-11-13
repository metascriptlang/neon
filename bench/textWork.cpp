#include <windows.h>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <string>
#include "../src/platform/windows/dwriteText.h"

static double frequency = 0;

static double now() {
	LARGE_INTEGER stamp;
	QueryPerformanceCounter(&stamp);
	return stamp.QuadPart * 1000.0 / frequency;
}

static void require(bool ok, const char *message) {
	if (ok) return;
	fprintf(stderr, "text-work: %s\n", message);
	exit(2);
}

static void profile(const char *name, const char *unit, int repetitions) {
	std::string text;
	for (int i = 0; i < repetitions; i++) text += unit;
	int units = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
		text.c_str(), (int)text.size(), nullptr, 0);
	require(units > 0, "invalid input UTF-8");
	for (int round = 0; round < 5; round++) {
		TextLabel label;
		float width = 0, height = 0;
		int built = TextLabel::LayoutsBuilt();
		auto report = [&](const char *mode, double elapsed, int calls,
			int expected, float limit) {
			int count = TextLabel::LayoutsBuilt() - built;
			require(count == expected, "unexpected layout rebuild count");
			require(std::isfinite(width) && std::isfinite(height) &&
				width > 0 && width <= limit + 1 && height > 0,
				"invalid measured bounds");
			printf("text-work %s %d %zu %d %s %.6f %d %d %.0f %.0f\n",
				name, repetitions, text.size(), round, mode,
				elapsed / calls, calls, count, width, height);
			built = TextLabel::LayoutsBuilt();
		};
		double started = now();
		label.SetText(text.c_str());
		label.Measure(320, 1, &width, &height);
		double elapsed = now() - started;
		require(label.Text().size() == (size_t)units, "UTF-16 length");
		report("initial", elapsed, 1, 1, 320);
		float initialWidth = width, initialHeight = height;

		started = now();
		for (int i = 0; i < 100; i++) {
			label.Measure(320, 1, &width, &height);
		}
		elapsed = now() - started;
		require(width == initialWidth && height == initialHeight,
			"cached metrics changed");
		report("cached", elapsed, 100, 0, 320);

		started = now();
		label.SetColor(Color{0.1f, 0.7f, 0.3f, 1});
		label.Measure(320, 1, &width, &height);
		elapsed = now() - started;
		require(width == initialWidth && height == initialHeight,
			"paint-only metrics changed");
		report("paint-only", elapsed, 1, 0, 320);

		started = now();
		label.Measure(160, 1, &width, &height);
		elapsed = now() - started;
		require(height >= initialHeight, "narrower text lost height");
		report("resize", elapsed, 1, 0, 160);

		std::string changed = text + " updated";
		started = now();
		label.SetText(changed.c_str());
		label.Measure(160, 1, &width, &height);
		elapsed = now() - started;
		require(label.Text().size() == (size_t)units + 8,
			"changed UTF-16 length");
		report("text-change", elapsed, 1, 1, 160);
	}
}

int main() {
	LARGE_INTEGER ticks;
	require(QueryPerformanceFrequency(&ticks), "no performance counter");
	frequency = (double)ticks.QuadPart;
	float width = 0, height = 0;
	TextLabel warm;
	warm.SetText("Neon العربية 123");
	warm.Measure(320, 1, &width, &height);
	for (int repetitions : {1, 16, 256, 4096}) {
		profile("latin", "Neon layout words ", repetitions);
		profile("mixed-arabic", "Neon العربية 123 ", repetitions);
	}
	return 0;
}
