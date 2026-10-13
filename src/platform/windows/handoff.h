#ifndef NEON_WINDOWS_HANDOFF_H
#define NEON_WINDOWS_HANDOFF_H

#ifdef __cplusplus
extern "C" {
#endif

void niwAttach(void *dcompDevice2, void *parentVisual2, float dpi, float logicalWidth, float logicalHeight);
int niwPump(void);
void niwShutdown(void);

#ifdef __cplusplus
}
#endif

#endif
