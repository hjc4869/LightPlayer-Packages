#include <cstdio>

extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
}

int main() {
  const AVCodec* decoder = avcodec_find_decoder(AV_CODEC_ID_HDMV_PGS_SUBTITLE);
  if (decoder == nullptr || decoder->type != AVMEDIA_TYPE_SUBTITLE) {
    std::fputs("PGS subtitle decoder is unavailable\n", stderr);
    return 1;
  }

  AVCodecContext* context = avcodec_alloc_context3(decoder);
  if (context == nullptr) {
    std::fputs("Could not allocate PGS decoder context\n", stderr);
    return 1;
  }

  const int result = avcodec_open2(context, decoder, nullptr);
  avcodec_free_context(&context);
  if (result < 0) {
    std::fprintf(stderr, "Could not open PGS subtitle decoder: %d\n", result);
    return 1;
  }

  if (av_find_input_format("sup") == nullptr) {
    std::fputs("SUP subtitle demuxer is unavailable\n", stderr);
    return 1;
  }

  std::puts("PGS subtitle decoder and SUP demuxer are available");
  return 0;
}