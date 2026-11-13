#include <windows.h>
#include "../../../ion/src/platform/common/inputEvents.h"
#include "windowsIonWheel.h"

int32_t nwiQueueWheelFrame(int32_t window) {
	LARGE_INTEGER frequency, counter;
	if (!QueryPerformanceFrequency(&frequency) || !QueryPerformanceCounter(&counter)) return -1;
	IonInputRecord wheel = {0};
	wheel.type = ION_INPUT_WHEEL;
	wheel.window = window;
	wheel.x = wheel.y = 10;
	wheel.p2 = -1;
	wheel.key = 1;
	if (ion_input_push_record(&wheel) != 0) return 0;
	IonInputRecord frame = {0};
	frame.type = ION_INPUT_FRAME;
	frame.window = window;
	frame.x = (double)counter.QuadPart * 1000.0 / (double)frequency.QuadPart + 10000.0;
	return ion_input_push_record(&frame) == 0 ? 2 : 1;
}
