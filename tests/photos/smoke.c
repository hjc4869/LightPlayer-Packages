#include <stdio.h>
#include <string.h>
#include "../../libraw/libraw/libraw.h"
#include "../../lcms2/include/lcms2.h"
#include "dng-fixtures.h"

#ifdef __EMSCRIPTEN_PTHREADS__
#include <pthread.h>
#endif

static int decode_dng(const unsigned char *data, size_t size, int floating)
{
    libraw_data_t *raw = libraw_init(0);
    if (!raw)
        return 10;
    raw->rawparams.options &= ~LIBRAW_RAWOPTIONS_CONVERTFLOAT_TO_INT;
    int result = libraw_open_buffer(raw, (void *)data, size);
    if (result == LIBRAW_SUCCESS)
        result = libraw_unpack(raw);
    if (result != LIBRAW_SUCCESS) {
        fprintf(stderr, "%s DNG decode failed: %s\n", floating ? "deflate" : "JPEG", libraw_strerror(result));
        libraw_close(raw);
        return 11;
    }
    int valid = raw->sizes.raw_width == 32 && raw->sizes.raw_height == 32;
    if (floating)
        valid = valid && raw->rawdata.float3_image && raw->rawdata.float3_image[0][0] == 0.5f;
    else
        valid = valid && raw->rawdata.color4_image && raw->rawdata.color4_image[0][0] > 0;
    libraw_close(raw);
    return valid ? 0 : 12;
}

static int run_smoke(void)
{
    unsigned capabilities = LIBRAW_CAPS_JPEG | LIBRAW_CAPS_ZLIB;
    if ((libraw_capabilities() & capabilities) != capabilities) {
        fputs("LibRaw JPEG/zlib support is missing\n", stderr);
        return 9;
    }
    if (strncmp(libraw_version(), "0.22.2", 6) != 0 ||
        cmsGetEncodedCMMversion() != LCMS_VERSION)
        return 1;

    libraw_data_t *raw = libraw_init(0);
    if (!raw)
        return 2;
    unsigned char invalid_raw[32] = {0};
    int result = libraw_open_buffer(raw, invalid_raw, sizeof(invalid_raw));
    libraw_close(raw);
    if (result != LIBRAW_FILE_UNSUPPORTED && result != LIBRAW_IO_ERROR)
        return 3;

    result = decode_dng(jpeg_dng, sizeof(jpeg_dng), 0);
    if (result != 0)
        return result;
    result = decode_dng(deflate_dng, sizeof(deflate_dng), 1);
    if (result != 0)
        return result;

    cmsHPROFILE profile = cmsCreate_sRGBProfile();
    if (!profile)
        return 4;
    cmsHTRANSFORM transform = cmsCreateTransform(profile, TYPE_RGB_8,
        profile, TYPE_RGB_8, INTENT_RELATIVE_COLORIMETRIC, 0);
    if (!transform) {
        cmsCloseProfile(profile);
        return 5;
    }
    unsigned char input[3] = {32, 128, 224};
    unsigned char output[3] = {0};
    cmsDoTransform(transform, input, output, 1);
    cmsDeleteTransform(transform);
    cmsCloseProfile(profile);
    if (memcmp(input, output, sizeof(input)) != 0)
        return 6;

    printf("LibRaw %s; Little CMS %d; JPEG/deflate DNG and native smoke tests passed\n",
        libraw_version(), cmsGetEncodedCMMversion());
    return 0;
}

#ifdef __EMSCRIPTEN_PTHREADS__
static void *run_thread_smoke(void *result)
{
    *(int *)result = run_smoke();
    return NULL;
}
#endif

int main(void)
{
    int result = run_smoke();
    if (result != 0)
        return result;
#ifdef __EMSCRIPTEN_PTHREADS__
    pthread_t thread;
    if (pthread_create(&thread, NULL, run_thread_smoke, &result) != 0)
        return 7;
    if (pthread_join(thread, NULL) != 0)
        return 8;
#endif
    return result;
}