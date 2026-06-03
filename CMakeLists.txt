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

# ── Toolchain helpers ─────────────────────────────────────────────────────────
include(cmake/sanitizers.cmake)
include(cmake/clang_fuzzing.cmake)

# ── Doom 3 BFG idLib (subset compiled as static lib for fuzzing) ──────────────
set(DOOM_SRC "${CMAKE_SOURCE_DIR}/src/doom-3-bfg")

if(EXISTS "${DOOM_SRC}/neo/idlib")
  file(GLOB_RECURSE IDLIB_SOURCES
    "${DOOM_SRC}/neo/idlib/*.cpp"
    "${DOOM_SRC}/neo/idlib/*.c"
  )

  # ── Exclude files that cannot compile on a headless Linux build ────────────
  # Windows platform layer
  list(FILTER IDLIB_SOURCES EXCLUDE REGEX ".*/win32/.*")
  list(FILTER IDLIB_SOURCES EXCLUDE REGEX ".*/sys/win32/.*")
  # macOS / Android / console stubs
  list(FILTER IDLIB_SOURCES EXCLUDE REGEX ".*/macos/.*")
  list(FILTER IDLIB_SOURCES EXCLUDE REGEX ".*/android/.*")
  list(FILTER IDLIB_SOURCES EXCLUDE REGEX ".*/stub/.*")
  # SoftwareCache pulls in ParallelJobList_JobHeaders which requires basetsd.h
  list(FILTER IDLIB_SOURCES EXCLUDE REGEX ".*SoftwareCache\\.cpp$")
  # ParallelJobList implementation has direct Windows thread primitives
  list(FILTER IDLIB_SOURCES EXCLUDE REGEX ".*ParallelJobList\\.cpp$")

  add_library(doom_idlib STATIC ${IDLIB_SOURCES})

  target_include_directories(doom_idlib PUBLIC
    "${DOOM_SRC}/neo"
    "${DOOM_SRC}/neo/idlib"
  )

  # ── Tell idLib we are on Linux ─────────────────────────────────────────────
  # sys_defines.h checks for these macros before allowing compilation.
  # Without them it emits #error Unknown Platform.
  target_compile_definitions(doom_idlib PUBLIC
    __linux__           # standard Linux predefined — belt-and-suspenders
    ID_PC_LINUX         # idLib's own Linux gate
    ID_PC               # required by several idLib headers
    FFFFFFFFFFFFFFFF=0xFFFFFFFFFFFFFFFFULL  # workaround for MSVC-ism in some headers
  )

  # Suppress warnings that would otherwise flood the build log for third-party code
  target_compile_options(doom_idlib PRIVATE
    -Wno-unused-variable
    -Wno-unused-function
    -Wno-deprecated-declarations
    -Wno-format
    -Wno-ignored-attributes
  )

  apply_sanitizer_flags(doom_idlib)

else()
  message(WARNING "Doom 3 BFG source not found at ${DOOM_SRC}. Run scripts/clone_doom.sh first.")
endif()

# ── Fuzzer harnesses ──────────────────────────────────────────────────────────
if(ENABLE_FUZZING)
  add_subdirectory(fuzz)
endif()
