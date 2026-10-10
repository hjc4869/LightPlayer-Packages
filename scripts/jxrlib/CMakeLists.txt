cmake_minimum_required(VERSION 3.16)
project(PhotosJxr VERSION 1.1 LANGUAGES C)

set(JXRLIB_SOURCE_DIR "${CMAKE_CURRENT_LIST_DIR}/../../jxrlib" CACHE PATH "jxrlib source checkout")
option(JXRLIB_BUILD_SHARED "Build shared JPEG XR libraries" ON)
option(JXRLIB_BUILD_STATIC "Build static JPEG XR libraries" ON)

file(COPY "${JXRLIB_SOURCE_DIR}/common" "${JXRLIB_SOURCE_DIR}/image"
  "${JXRLIB_SOURCE_DIR}/jxrgluelib" DESTINATION "${CMAKE_CURRENT_BINARY_DIR}/source")
set(JXRLIB_SOURCE_DIR "${CMAKE_CURRENT_BINARY_DIR}/source")
file(READ "${JXRLIB_SOURCE_DIR}/image/sys/ansi.h" ansi_header)
string(REPLACE "#if __LP64__" "#if defined(__LP64__) || defined(_WIN64)" ansi_header "${ansi_header}")
file(WRITE "${JXRLIB_SOURCE_DIR}/image/sys/ansi.h" "${ansi_header}")
foreach(source image/sys/strcodec.c image/decode/segdec.c)
  file(READ "${JXRLIB_SOURCE_DIR}/${source}" source_text)
  string(REPLACE "_byteswap_ulong" "photos_jxr_byteswap_ulong" source_text "${source_text}")
  file(WRITE "${JXRLIB_SOURCE_DIR}/${source}" "${source_text}")
endforeach()
file(READ "${JXRLIB_SOURCE_DIR}/image/decode/JXRTranscode.c" transcode_source)
string(REPLACE "EXTERN_C Void StrIODecTerm" "EXTERN_C Int StrIODecTerm" transcode_source "${transcode_source}")
string(REPLACE "EXTERN_C Void StrIOEncTerm" "EXTERN_C Int StrIOEncTerm" transcode_source "${transcode_source}")
file(WRITE "${JXRLIB_SOURCE_DIR}/image/decode/JXRTranscode.c" "${transcode_source}")

set(codec_sources
  image/sys/adapthuff.c image/sys/image.c image/sys/strcodec.c
  image/sys/strPredQuant.c image/sys/strTransform.c image/sys/perfTimerANSI.c
  image/decode/decode.c image/decode/postprocess.c image/decode/segdec.c
  image/decode/strdec.c image/decode/strInvTransform.c
  image/decode/strPredQuantDec.c image/decode/JXRTranscode.c
  image/encode/encode.c image/encode/segenc.c image/encode/strenc.c
  image/encode/strFwdTransform.c image/encode/strPredQuantEnc.c)
set(glue_sources
  jxrgluelib/JXRGlue.c jxrgluelib/JXRMeta.c
  jxrgluelib/JXRGluePFC.c jxrgluelib/JXRGlueJxr.c)
list(TRANSFORM codec_sources PREPEND "${JXRLIB_SOURCE_DIR}/")
list(TRANSFORM glue_sources PREPEND "${JXRLIB_SOURCE_DIR}/")

add_library(jpegxr_objects OBJECT ${codec_sources})
add_library(jxrglue_objects OBJECT ${glue_sources})
foreach(library jpegxr jxrglue)
  set_target_properties(${library}_objects PROPERTIES
    POSITION_INDEPENDENT_CODE ON C_VISIBILITY_PRESET default C_STANDARD 99)
  target_include_directories(${library}_objects PRIVATE
    "${JXRLIB_SOURCE_DIR}/common/include" "${JXRLIB_SOURCE_DIR}/image/sys"
    "${JXRLIB_SOURCE_DIR}/jxrgluelib")
  target_compile_definitions(${library}_objects PRIVATE __ANSI__ DISABLE_PERF_MEASUREMENT)
  if(MSVC)
    target_compile_definitions(${library}_objects PRIVATE _CRT_SECURE_NO_WARNINGS)
    target_compile_options(${library}_objects PRIVATE /UWIN32 "/FI${CMAKE_CURRENT_LIST_DIR}/compat.h")
  else()
    target_compile_options(${library}_objects PRIVATE -fno-strict-aliasing -UWIN32
      -include "${CMAKE_CURRENT_LIST_DIR}/compat.h")
  endif()
  if(JXRLIB_BUILD_STATIC)
    add_library(${library}_static STATIC $<TARGET_OBJECTS:${library}_objects>)
    set_target_properties(${library}_static PROPERTIES OUTPUT_NAME ${library} PREFIX lib)
    install(TARGETS ${library}_static ARCHIVE DESTINATION lib)
  endif()
  if(JXRLIB_BUILD_SHARED)
    add_library(${library} SHARED $<TARGET_OBJECTS:${library}_objects>)
    set_target_properties(${library} PROPERTIES
      PREFIX lib WINDOWS_EXPORT_ALL_SYMBOLS ON
      INSTALL_RPATH "$ORIGIN" INSTALL_NAME_DIR "@rpath")
    if(APPLE)
      set_target_properties(${library} PROPERTIES INSTALL_RPATH "@loader_path")
    elseif(UNIX)
      target_link_options(${library} PRIVATE -Wl,--no-undefined)
    endif()
    install(TARGETS ${library} RUNTIME DESTINATION bin LIBRARY DESTINATION lib
      ARCHIVE DESTINATION lib)
  endif()
endforeach()

if(JXRLIB_BUILD_SHARED)
  target_link_libraries(jxrglue PRIVATE jpegxr)
  if(NOT WIN32)
    target_link_libraries(jpegxr PRIVATE m)
    target_link_libraries(jxrglue PRIVATE m)
  endif()
endif()