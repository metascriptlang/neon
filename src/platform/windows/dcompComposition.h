#pragma once
#include "composition.h"

ICompositionContext *CreateDCompContext(void *dcompDevice2);
IVisual *AdoptDCompVisual(ICompositionContext *context, void *visual2);
