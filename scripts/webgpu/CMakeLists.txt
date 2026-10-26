cmake_minimum_required(VERSION 3.22)
project(LightStudioWebGPU LANGUAGES C CXX)

find_package(Python3 REQUIRED COMPONENTS Interpreter)
include(FetchContent)
FetchContent_Declare(dawn
  URL "https://github.com/google/dawn/archive/refs/tags/${LIGHTSTUDIO_DAWN_TAG}.zip"
  URL_HASH "SHA1=${LIGHTSTUDIO_DAWN_ARCHIVE_SHA1}"
  PATCH_COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/../webgpu-native-bindings.py" prepare-source <SOURCE_DIR>
)
FetchContent_MakeAvailable(dawn)