cmake_minimum_required(VERSION 3.22)
project(fuzzing_experiments LANGUAGES C CXX)

set(CMAKE_C_STANDARD   11)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# ── Options ──────────────────────────────────────────────────────────────────
option(ENABLE_FUZZING  "Build LibFuzzer harnesses"          OFF)
option(ENABLE_ASAN     "Enable AddressSanitizer"           OFF)
option(ENABLE_UBSAN    "Enable UndefinedBehaviorSanitizer" OFF)
option(ENABLE_MSAN     "Enable MemorySanitizer"            OFF)
option(ENABLE_COVERAGE "Emit coverage instrumentation"     OFF)

# ── Toolchain helpers ────────────────────────────────────────────────────────
include(cmake/sanitizers.cmake)
include(cmake/clang_fuzzing.cmake)

# ── Doom 3 BFG idLib (subset compiled as static lib for fuzzing) ─────────────
set(DOOM_SRC "${CMAKE_SOURCE_DIR}/src/doom-3-bfg")

if(EXISTS "${DOOM_SRC}/neo/idlib")
  file(GLOB_RECURSE IDLIB_SOURCES
    "${DOOM_SRC}/neo/idlib/*.cpp"
    "${DOOM_SRC}/neo/idlib/*.c"
  )
  # Exclude platform-specific files that won't compile on Linux headlessly
  list(FILTER IDLIB_SOURCES EXCLUDE REGEX ".*/(win32|macos|android)/.*")

  add_library(doom_idlib STATIC ${IDLIB_SOURCES})
  target_include_directories(doom_idlib PUBLIC
    "${DOOM_SRC}/neo"
    "${DOOM_SRC}/neo/idlib"
  )
  apply_sanitizer_flags(doom_idlib)
else()
  message(WARNING "Doom 3 BFG source not found at ${DOOM_SRC}. Run scripts/clone_doom.sh first.")
endif()

# ── Fuzzer harnesses ─────────────────────────────────────────────────────────
if(ENABLE_FUZZING)
  add_subdirectory(fuzz)
endif()
