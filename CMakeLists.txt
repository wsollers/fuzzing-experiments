cmake_minimum_required(VERSION 3.22)
project(fuzzing_experiments LANGUAGES C CXX)

set(CMAKE_C_STANDARD   11)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# ── Options ───────────────────────────────────────────────────────────────────
option(ENABLE_FUZZING  "Build LibFuzzer harnesses"          OFF)
option(ENABLE_ASAN     "Enable AddressSanitizer"           OFF)
option(ENABLE_UBSAN    "Enable UndefinedBehaviorSanitizer" OFF)
option(ENABLE_MSAN     "Enable MemorySanitizer"            OFF)
option(ENABLE_COVERAGE "Emit coverage instrumentation"     OFF)

# ── Toolchain helpers ─────────────────────────────────────────────────────────
include(cmake/sanitizers.cmake)
include(cmake/clang_fuzzing.cmake)
if(WIN32)
  include(cmake/windows_idlib.cmake)
endif()

# ── Doom 3 BFG idLib (compiled as static lib for fuzzing) ────────────────────
set(DOOM_SRC "${CMAKE_SOURCE_DIR}/src/doom-3-bfg")

if(EXISTS "${DOOM_SRC}/neo/idlib")
  file(GLOB_RECURSE IDLIB_SOURCES
    "${DOOM_SRC}/neo/idlib/*.cpp"
    "${DOOM_SRC}/neo/idlib/*.c"
  )

  # ── Exclude files that cannot compile headlessly on any platform ───────────
  # macOS / Android / console stubs
  list(FILTER IDLIB_SOURCES EXCLUDE REGEX ".*/macos/.*")
  list(FILTER IDLIB_SOURCES EXCLUDE REGEX ".*/android/.*")
  list(FILTER IDLIB_SOURCES EXCLUDE REGEX ".*/stub/.*")

  if(WIN32)
    # On Windows _WIN32 is defined naturally so the platform layer compiles,
    # but a few files pull in GPU/job system headers that require a full engine
    # build.  Exclude them so the static lib stays self-contained.
    list(FILTER IDLIB_SOURCES EXCLUDE REGEX ".*SoftwareCache\\.cpp$")
    list(FILTER IDLIB_SOURCES EXCLUDE REGEX ".*ParallelJobList\\.cpp$")
  else()
    # Linux: additionally exclude the win32 platform layer
    list(FILTER IDLIB_SOURCES EXCLUDE REGEX ".*/win32/.*")
    list(FILTER IDLIB_SOURCES EXCLUDE REGEX ".*/sys/win32/.*")
    list(FILTER IDLIB_SOURCES EXCLUDE REGEX ".*SoftwareCache\\.cpp$")
    list(FILTER IDLIB_SOURCES EXCLUDE REGEX ".*ParallelJobList\\.cpp$")
  endif()

  add_library(doom_idlib STATIC ${IDLIB_SOURCES})

  target_include_directories(doom_idlib PUBLIC
    "${DOOM_SRC}/neo"
    "${DOOM_SRC}/neo/idlib"
  )

  if(WIN32)
    # Windows: _WIN32 already defined; apply MSVC/clang-cl compatibility flags
    apply_windows_idlib_flags(doom_idlib)
  else()
    # Linux: inject the platform macros idLib needs
    target_compile_definitions(doom_idlib PUBLIC
      __linux__
      ID_PC_LINUX
      ID_PC
    )
    target_compile_options(doom_idlib PRIVATE
      -Wno-unused-variable
      -Wno-unused-function
      -Wno-deprecated-declarations
      -Wno-format
      -Wno-ignored-attributes
    )
  endif()

  apply_sanitizer_flags(doom_idlib)

else()
  message(WARNING
    "Doom 3 BFG source not found at ${DOOM_SRC}. "
    "Run scripts/clone_doom.sh (Linux) or scripts/clone_doom.ps1 (Windows) first."
  )
endif()

# ── Fuzzer harnesses ──────────────────────────────────────────────────────────
if(ENABLE_FUZZING)
  add_subdirectory(fuzz)
endif()
