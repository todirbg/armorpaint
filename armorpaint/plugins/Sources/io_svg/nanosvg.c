// nanosvg bridge for armorpaint

#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <math.h>
// #define NANOSVG_ALL_COLOR_KEYWORDS
#define NANOSVG_IMPLEMENTATION
#include "nanosvg.h"
#define NANOSVGRAST_IMPLEMENTATION
#include "nanosvgrast.h"
#ifdef WITH_PLUGIN_EMBED
#define EMSCRIPTEN_KEEPALIVE
#else
#include <emscripten.h>
#endif

static uint8_t *buffer = NULL;
static uint32_t bufferLength = 0;
static int bufOff; /* Pointer to null terminated svg string input */
static int pixelsOff; /* Rasterized pixel output */
static int w;
static int h;

EMSCRIPTEN_KEEPALIVE uint8_t *io_svg_getBuffer() { return buffer; }
EMSCRIPTEN_KEEPALIVE uint32_t io_svg_getBufferLength() { return bufferLength; }

static int allocate(int size) {
	#ifdef WITH_PLUGIN_EMBED
	size += size % 4; // Byte align
	#endif
	bufferLength += size;
	buffer = buffer == NULL ? (uint8_t *)malloc(bufferLength) : (uint8_t *)realloc(buffer, bufferLength);
	return bufferLength - size;
}

EMSCRIPTEN_KEEPALIVE int io_svg_init(int buf_size) {
	bufOff = allocate(sizeof(char) * buf_size);
	return bufOff;
}

EMSCRIPTEN_KEEPALIVE void io_svg_parse() {
	char *buf = &buffer[bufOff];
	NSVGimage *image = nsvgParse(buf, "px", 96.0f);
	w = (int)image->width;
	h = (int)image->height;
	pixelsOff = allocate(sizeof(unsigned char) * w * h * 4);
	unsigned char *pixels = &buffer[pixelsOff];
	struct NSVGrasterizer *rast;
	rast = nsvgCreateRasterizer();
	nsvgRasterize(rast, image, 0, 0, 1, pixels, w, h, w * 4);
	nsvgDelete(image);
	nsvgDeleteRasterizer(rast);
}

EMSCRIPTEN_KEEPALIVE int io_svg_get_pixels() { return pixelsOff; }
EMSCRIPTEN_KEEPALIVE int io_svg_get_pixels_w() { return w; }
EMSCRIPTEN_KEEPALIVE int io_svg_get_pixels_h() { return h; }

EMSCRIPTEN_KEEPALIVE void io_svg_destroy() {
	free(buffer);
	buffer = NULL;
}
