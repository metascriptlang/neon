#include <stdint.h>
void npiBegin(void);
void npiDrag(float x, double time);
void npiTick(void);
void npiUp(void);
void npiResize(void);
void npiDetach(void);
void npiControl(void);
void npiReenter(void);
void npiUnregister(void);
void npiShutdown(void);
int32_t npiMoves(void);
int32_t npiOrder(void);
int32_t npiRequests(void);
float npiLastX(void);
double npiLastTime(void);
