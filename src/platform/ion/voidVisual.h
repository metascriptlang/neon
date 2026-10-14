#ifndef NEON_ION_VOID_VISUAL_H
#define NEON_ION_VOID_VISUAL_H

#ifdef __cplusplus
extern "C" {
#endif

void *voidVisualAttach(void *device, void *root, long long swapChain);
void  voidVisualDetach(void *root, void *visual);

#ifdef __cplusplus
}
#endif

#endif
