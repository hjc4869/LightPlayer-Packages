#include <cassert>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <vector>

#include <emscripten/threading.h>
#include <jxl/cms.h>
#include <skcms.h>

static std::vector<uint8_t> read_profile(const char* path) {
  FILE* file = std::fopen(path, "rb");
  assert(file != nullptr);
  assert(std::fseek(file, 0, SEEK_END) == 0);
  const long size = std::ftell(file);
  assert(size > 0);
  std::rewind(file);
  std::vector<uint8_t> bytes(static_cast<size_t>(size));
  assert(std::fread(bytes.data(), 1, bytes.size(), file) == bytes.size());
  assert(std::fclose(file) == 0);
  return bytes;
}

int main() {
#ifdef __EMSCRIPTEN_PTHREADS__
  assert(!emscripten_is_main_runtime_thread());
#endif
  const auto source_icc = read_profile("/display-p3.icc");
  const auto destination_icc = read_profile("/srgb.icc");
  skcms_ICCProfile source_profile;
  skcms_ICCProfile destination_profile;
  assert(skcms_Parse(source_icc.data(), source_icc.size(), &source_profile));
  assert(skcms_Parse(destination_icc.data(), destination_icc.size(), &destination_profile));

  const float pixels[] = {0.25f, 0.5f, 0.75f, 0.8f, 0.3f, 0.1f};
  float expected[6] = {};
  assert(skcms_Transform(pixels, skcms_PixelFormat_RGB_fff, skcms_AlphaFormat_Opaque,
                         &source_profile, expected, skcms_PixelFormat_RGB_fff,
                         skcms_AlphaFormat_Opaque, &destination_profile, 2));
  assert(std::fabs(expected[0] - pixels[0]) > 0.01f);

  const JxlCmsInterface* cms = JxlGetDefaultCms();
  assert(cms != nullptr);
  JxlColorProfile input = {};
  JxlColorProfile output = {};
  input.icc.data = source_icc.data();
  input.icc.size = source_icc.size();
  input.num_channels = 3;
  output.icc.data = destination_icc.data();
  output.icc.size = destination_icc.size();
  output.num_channels = 3;
  JXL_BOOL cmyk = JXL_FALSE;
  assert(cms->set_fields_from_icc(cms->set_fields_data, input.icc.data, input.icc.size,
                                 &input.color_encoding, &cmyk));
  assert(cmyk == JXL_FALSE);
  assert(cms->set_fields_from_icc(cms->set_fields_data, output.icc.data, output.icc.size,
                                 &output.color_encoding, &cmyk));
  assert(cmyk == JXL_FALSE);
  void* transform = cms->init(cms->init_data, 1, 2, &input, &output, 255.0f);
  assert(transform != nullptr);
  float actual[6] = {};
  assert(cms->run(transform, 0, pixels, actual, 2));
  cms->destroy(transform);
  for (size_t channel = 0; channel < 6; ++channel) {
    assert(std::fabs(actual[channel] - expected[channel]) < 0.001f);
  }
  std::puts("skcms coexistence and Display-P3 conversion passed");
  return 0;
}