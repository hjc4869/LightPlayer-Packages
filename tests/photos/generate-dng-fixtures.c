#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <jpeglib.h>
#include <zlib.h>

static void put16(unsigned char *buffer, unsigned value)
{
    buffer[0] = value;
    buffer[1] = value >> 8;
}

static void put32(unsigned char *buffer, unsigned value)
{
    put16(buffer, value);
    put16(buffer + 2, value >> 16);
}

static void emit_dng(const char *name, const unsigned char *payload, unsigned size, int floating)
{
    unsigned char image[8192] = {'I', 'I', 42, 0, 8, 0, 0, 0};
    unsigned tags[][4] = {
        {254, 4, 1, 0}, {256, 4, 1, 32}, {257, 4, 1, 32},
        {258, 3, 3, 256}, {259, 3, 1, floating ? 8 : 34892},
        {262, 3, 1, 34892}, {277, 3, 1, 3}, {284, 3, 1, 1},
        {317, 3, 1, floating ? 3 : 1},
        {322, 4, 1, 32}, {323, 4, 1, 32}, {324, 4, 1, 512},
        {325, 4, 1, size}, {339, 3, 1, floating ? 3 : 1},
        {50706, 1, 4, 0x00000401}, {50707, 1, 4, 0x00000401},
        {50708, 2, 16, 264}
    };
    unsigned count = sizeof(tags) / sizeof(tags[0]);
    put16(image + 8, count);
    for (unsigned index = 0; index < count; ++index) {
        unsigned char *entry = image + 10 + index * 12;
        put16(entry, tags[index][0]);
        put16(entry + 2, tags[index][1]);
        put32(entry + 4, tags[index][2]);
        put32(entry + 8, tags[index][3]);
    }
    for (unsigned channel = 0; channel < 3; ++channel)
        put16(image + 256 + channel * 2, floating ? 32 : 8);
    memcpy(image + 264, "Photos Test RGB", 16);
    memcpy(image + 512, payload, size);
    printf("static const unsigned char %s[] = {\n", name);
    for (unsigned index = 0; index < 512 + size; ++index)
        printf("0x%02x,%s", image[index], index % 16 == 15 || index + 1 == 512 + size ? "\n" : " ");
    puts("};");
}

int main(void)
{
    struct jpeg_compress_struct compressor;
    struct jpeg_error_mgr error;
    unsigned char *jpeg = NULL;
    unsigned long jpeg_size = 0;
    compressor.err = jpeg_std_error(&error);
    jpeg_create_compress(&compressor);
    jpeg_mem_dest(&compressor, &jpeg, &jpeg_size);
    compressor.image_width = compressor.image_height = 32;
    compressor.input_components = 3;
    compressor.in_color_space = JCS_RGB;
    jpeg_set_defaults(&compressor);
    jpeg_set_quality(&compressor, 95, 1);
    jpeg_start_compress(&compressor, 1);
    unsigned char row[32 * 3];
    memset(row, 128, sizeof(row));
    while (compressor.next_scanline < compressor.image_height) {
        JSAMPROW rows[] = {row};
        jpeg_write_scanlines(&compressor, rows, 1);
    }
    jpeg_finish_compress(&compressor);
    emit_dng("jpeg_dng", jpeg, jpeg_size, 0);
    jpeg_destroy_compress(&compressor);
    free(jpeg);

    unsigned char pixels[32 * 32 * 3 * 4] = {0};
    for (unsigned row_index = 0; row_index < 32; ++row_index) {
        unsigned char *encoded = pixels + row_index * 32 * 3 * 4;
        memset(encoded, 0x3f, 32 * 3);
        for (unsigned byte = 32 * 3 * 4 - 1; byte >= 3; --byte)
            encoded[byte] -= encoded[byte - 3];
    }
    unsigned char deflated[1024];
    unsigned long deflated_size = sizeof(deflated);
    if (compress2(deflated, &deflated_size, pixels, sizeof(pixels), 9) != Z_OK)
        return 1;
    emit_dng("deflate_dng", deflated, deflated_size, 1);
    return 0;
}