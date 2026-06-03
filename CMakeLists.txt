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

# clang-cl's LibFuzzer runtime for Windows is built against the static CRT.
# Keep all fuzz-instrumented objects on the same runtime to avoid
# /failifmismatch errors at link time.
if(WIN32 AND CMAKE_CXX_COMPILER_ID STREQUAL "Clang" AND ENABLE_FUZZING)
  set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded")
endif()

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

  # ── Exclude files that cannot compile headlessly on any platform ──────────
  list(FILTER IDLIB_SOURCES EXCLUDE REGEX ".*/macos/.*")
  list(FILTER IDLIB_SOURCES EXCLUDE REGEX ".*/android/.*")
  list(FILTER IDLIB_SOURCES EXCLUDE REGEX ".*/stub/.*")
  # These pull in GPU/job-system headers requiring a full engine build
  list(FILTER IDLIB_SOURCES EXCLUDE REGEX ".*SoftwareCache\\.cpp$")
  list(FILTER IDLIB_SOURCES EXCLUDE REGEX ".*ParallelJobList\\.cpp$")

  if(NOT WIN32)
    list(FILTER IDLIB_SOURCES EXCLUDE REGEX ".*/win32/.*")
    list(FILTER IDLIB_SOURCES EXCLUDE REGEX ".*/sys/win32/.*")
  endif()

  add_library(doom_idlib STATIC ${IDLIB_SOURCES})

  target_include_directories(doom_idlib PUBLIC
    "${DOOM_SRC}/neo"
    "${DOOM_SRC}/neo/idlib"
  )

  if(WIN32)
    apply_windows_idlib_flags(doom_idlib)

    # idLib's precompiled.h pulls in framework headers that use std::auto_ptr,
    # which was removed in C++17.  _HAS_AUTO_PTR_ETC=1 re-enables it in the
    # MSVC/clang-cl STL without changing the language standard for our own code.
    # std::random_shuffle was also removed in C++17 -- same macro covers it.
    target_compile_definitions(doom_idlib PUBLIC
      _HAS_AUTO_PTR_ETC=1
    )
  else()
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

  add_library(doom_savegame_file STATIC
    "${DOOM_SRC}/neo/framework/Compressor.cpp"
    "${DOOM_SRC}/neo/framework/File.cpp"
    "${DOOM_SRC}/neo/framework/File_SaveGame.cpp"
    "${DOOM_SRC}/neo/framework/Unzip.cpp"
    "${DOOM_SRC}/neo/framework/zlib/adler32.c"
    "${DOOM_SRC}/neo/framework/zlib/compress.c"
    "${DOOM_SRC}/neo/framework/zlib/crc32.c"
    "${DOOM_SRC}/neo/framework/zlib/deflate.c"
    "${DOOM_SRC}/neo/framework/zlib/infback.c"
    "${DOOM_SRC}/neo/framework/zlib/inffast.c"
    "${DOOM_SRC}/neo/framework/zlib/inflate.c"
    "${DOOM_SRC}/neo/framework/zlib/inftrees.c"
    "${DOOM_SRC}/neo/framework/zlib/trees.c"
    "${DOOM_SRC}/neo/framework/zlib/uncompr.c"
    "${DOOM_SRC}/neo/framework/zlib/zutil.c"
  )

  target_include_directories(doom_savegame_file PUBLIC
    "${DOOM_SRC}/neo"
    "${DOOM_SRC}/neo/idlib"
    "${DOOM_SRC}/neo/framework"
  )

  target_link_libraries(doom_savegame_file PUBLIC doom_idlib)

  if(WIN32)
    apply_windows_idlib_flags(doom_savegame_file)
    target_compile_definitions(doom_savegame_file PUBLIC
      _HAS_AUTO_PTR_ETC=1
    )
  else()
    target_compile_definitions(doom_savegame_file PUBLIC
      __linux__
      ID_PC_LINUX
      ID_PC
    )
    target_compile_options(doom_savegame_file PRIVATE
      -Wno-unused-variable
      -Wno-unused-function
      -Wno-deprecated-declarations
      -Wno-format
      -Wno-ignored-attributes
    )
  endif()

  apply_sanitizer_flags(doom_savegame_file)

  add_library(doom_savegame_restore STATIC
    "fuzz/doom_savegame_restore_minimal.cpp"
  )

  target_include_directories(doom_savegame_restore PUBLIC
    "${DOOM_SRC}/neo"
    "${DOOM_SRC}/neo/idlib"
    "${DOOM_SRC}/neo/framework"
    "${DOOM_SRC}/neo/d3xp"
    "${DOOM_SRC}/neo/d3xp/gamesys"
  )

  target_link_libraries(doom_savegame_restore PUBLIC doom_savegame_file)

  if(WIN32)
    apply_windows_idlib_flags(doom_savegame_restore)
    target_compile_definitions(doom_savegame_restore PUBLIC
      _HAS_AUTO_PTR_ETC=1
    )
  else()
    target_compile_definitions(doom_savegame_restore PUBLIC
      __linux__
      ID_PC_LINUX
      ID_PC
    )
    target_compile_options(doom_savegame_restore PRIVATE
      -Wno-unused-variable
      -Wno-unused-function
      -Wno-deprecated-declarations
      -Wno-format
      -Wno-ignored-attributes
    )
  endif()

  apply_sanitizer_flags(doom_savegame_restore)

else()
  message(WARNING
    "Doom 3 BFG source not found at ${DOOM_SRC}. "
    "Run scripts/clone_doom.sh (Linux) or clone with git first."
  )
endif()

# ── Fuzzer harnesses ──────────────────────────────────────────────────────────
if(ENABLE_FUZZING)
  add_subdirectory(fuzz)
endif()
