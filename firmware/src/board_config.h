#pragma once

#ifndef LED_DATA_PIN
#error "LED_DATA_PIN must be defined by the PlatformIO environment"
#endif

#ifndef LED_COUNT
#define LED_COUNT 64
#endif

#ifndef LED_COLOR_ORDER
#define LED_COLOR_ORDER NEO_GRB
#endif

#ifndef MATRIX_WIDTH
#define MATRIX_WIDTH 8
#endif

#ifndef MATRIX_HEIGHT
#define MATRIX_HEIGHT 8
#endif

#ifndef MATRIX_SERPENTINE
#define MATRIX_SERPENTINE 0
#endif

#ifndef MATRIX_ROTATION
#define MATRIX_ROTATION 0
#endif

static_assert(LED_COUNT == MATRIX_WIDTH * MATRIX_HEIGHT,
              "LED_COUNT must match the matrix dimensions");
static_assert(MATRIX_WIDTH == 8 && MATRIX_HEIGHT == 8,
              "The 5/3 display currently requires an 8x8 matrix");

#if MATRIX_SERPENTINE != 0 && MATRIX_SERPENTINE != 1
#error "MATRIX_SERPENTINE must be 0 or 1"
#endif

#if MATRIX_ROTATION != 0 && MATRIX_ROTATION != 90 && MATRIX_ROTATION != 180 && MATRIX_ROTATION != 270
#error "MATRIX_ROTATION must be 0, 90, 180, or 270"
#endif
