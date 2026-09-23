cmake_minimum_required(VERSION 3.24)
project(LightStudioSqliteVec VERSION 0.1.9 LANGUAGES C)

include(FetchContent)
FetchContent_Declare(sqlite_vec
  URL https://github.com/asg017/sqlite-vec/releases/download/v0.1.9/sqlite-vec-0.1.9-amalgamation.tar.gz
  URL_HASH SHA256=3acd67cb4aff080c7050926fd3cf8227905fe5b7ee3829d8ee5024ab1283cf61
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE
  TLS_VERIFY TRUE
)
FetchContent_Declare(sqlite_headers
  URL https://www.sqlite.org/2025/sqlite-amalgamation-3500400.zip
  URL_HASH SHA256=1d3049dd0f830a025a53105fc79fd2ab9431aea99e137809d064d8ee8356b032
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE
  TLS_VERIFY TRUE
)
FetchContent_MakeAvailable(sqlite_vec sqlite_headers)

file(READ "${sqlite_vec_SOURCE_DIR}/sqlite-vec.c" sqlite_vec_source)
string(REPLACE
  "static unsigned int __builtin_popcountl(unsigned int x)"
  "static unsigned int __builtin_popcountl(unsigned long long x)"
  sqlite_vec_source "${sqlite_vec_source}"
)
if(EMSCRIPTEN)
  string(REPLACE "__builtin_popcountl(" "__builtin_popcountll(" sqlite_vec_source "${sqlite_vec_source}")
endif()
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/sqlite-vec.c" "${sqlite_vec_source}")
if(EMSCRIPTEN)
  add_library(vec0 STATIC "${CMAKE_CURRENT_BINARY_DIR}/sqlite-vec.c")
else()
  add_library(vec0 SHARED "${CMAKE_CURRENT_BINARY_DIR}/sqlite-vec.c")
endif()
target_include_directories(vec0 PRIVATE "${sqlite_vec_SOURCE_DIR}" "${sqlite_headers_SOURCE_DIR}")
set_target_properties(vec0 PROPERTIES
  PREFIX ""
  C_STANDARD 11
  C_STANDARD_REQUIRED YES
  MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>"
)

if(ANDROID)
  set_target_properties(vec0 PROPERTIES PREFIX "lib")
endif()

set(sqlite_linking "extension API table only; no SQLite engine")
if(EMSCRIPTEN)
  option(SQLITE_VEC_WASM_THREADS "Build for a pthread-enabled WebAssembly runtime" OFF)
  set_target_properties(vec0 PROPERTIES PREFIX "lib")
  target_compile_definitions(vec0 PRIVATE SQLITE_CORE)
  if(SQLITE_VEC_WASM_THREADS)
    target_compile_options(vec0 PRIVATE -pthread)
  endif()
  set(sqlite_linking "static calls to application-provided SQLite; no SQLite engine")
elseif(MSVC)
  target_compile_definitions(vec0 PRIVATE _CRT_SECURE_NO_WARNINGS)
elseif(APPLE)
  set_target_properties(vec0 PROPERTIES INSTALL_NAME_DIR "@rpath" BUILD_WITH_INSTALL_NAME_DIR YES)
  target_link_options(vec0 PRIVATE "LINKER:-exported_symbol,_sqlite3_vec_init")
else()
  target_link_libraries(vec0 PRIVATE m)
  file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/vec0.exports" "{ global: sqlite3_vec_init; local: *; };\n")
  target_link_options(vec0 PRIVATE
    "LINKER:--version-script=${CMAKE_CURRENT_BINARY_DIR}/vec0.exports"
    "LINKER:-z,defs"
  )
  if(ANDROID)
    target_link_options(vec0 PRIVATE "LINKER:-z,max-page-size=16384")
  endif()
endif()

set(SQLITE_VEC_RID "" CACHE STRING "NuGet runtime identifier")
file(DOWNLOAD
  https://raw.githubusercontent.com/asg017/sqlite-vec/e9f598abfa0c06b328d8fe5da9c3760cce74be10/LICENSE-MIT
  "${CMAKE_CURRENT_BINARY_DIR}/LICENSE-MIT"
  EXPECTED_HASH SHA256=6ce72bbe12d975bd5286e5ab0a064c069693300c47bccbc57bec18485f1621ea
  TLS_VERIFY ON
)
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/build-info.txt"
  "sqlite-vec ${PROJECT_VERSION}\nSource: e9f598abfa0c06b328d8fe5da9c3760cce74be10\nAmalgamation SHA256: 3acd67cb4aff080c7050926fd3cf8227905fe5b7ee3829d8ee5024ab1283cf61\nLocal fix: MSVC ARM64 64-bit popcount argument\nRID: ${SQLITE_VEC_RID}\nSQLite headers: 3.50.4\nSQLite linking: ${sqlite_linking}\nC compiler: ${CMAKE_C_COMPILER_ID} ${CMAKE_C_COMPILER_VERSION}\n"
)
if(EMSCRIPTEN)
  file(APPEND "${CMAKE_CURRENT_BINARY_DIR}/build-info.txt"
    "WASM threads: ${SQLITE_VEC_WASM_THREADS}\nLocal fix: WASM32 64-bit popcount builtin\n")
endif()
install(FILES "$<TARGET_FILE:vec0>" "${CMAKE_CURRENT_BINARY_DIR}/build-info.txt" DESTINATION .)
install(FILES "${CMAKE_CURRENT_BINARY_DIR}/LICENSE-MIT" DESTINATION licenses/sqlite-vec)