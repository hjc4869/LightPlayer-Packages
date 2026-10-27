cmake_minimum_required(VERSION 3.22)
project(LightStudioWebGPU LANGUAGES C CXX)

find_package(Python3 REQUIRED COMPONENTS Interpreter)
include(FetchContent)
FetchContent_Declare(dawn
  GIT_REPOSITORY "https://dawn.googlesource.com/dawn"
  GIT_TAG "${LIGHTSTUDIO_DAWN_REVISION}"
  GIT_PROGRESS TRUE
  GIT_SUBMODULES ""
  PATCH_COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/../webgpu-native-bindings.py" prepare-source <SOURCE_DIR>
)
FetchContent_MakeAvailable(dawn)