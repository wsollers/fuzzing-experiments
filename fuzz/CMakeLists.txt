# fuzz/CMakeLists.txt
# Register all fuzzer harness targets.

if(NOT TARGET doom_idlib)
  message(WARNING "doom_idlib not found — fuzzer targets that depend on it will be skipped.")
  return()
endif()

# Helper include (already included at top level, safe to re-include)
include("${CMAKE_SOURCE_DIR}/cmake/clang_fuzzing.cmake")

# ── idLib string / math fuzzer ─────────────────────────────────────────────────────
add_fuzzer_target(fuzz_doom_idlib
  SOURCES doom_idlib_harness.cpp
  LIBS    doom_idlib
)

target_include_directories(fuzz_doom_idlib PRIVATE
  "${CMAKE_SOURCE_DIR}/src/doom-3-bfg/neo"
)

# ── Config / script parser fuzzer ───────────────────────────────────────────────
add_fuzzer_target(fuzz_doom_parser
  SOURCES doom_parser_harness.cpp
  LIBS    doom_idlib
)

target_include_directories(fuzz_doom_parser PRIVATE
  "${CMAKE_SOURCE_DIR}/src/doom-3-bfg/neo"
)

# To add a new harness:
#   add_fuzzer_target(fuzz_my_target
#     SOURCES my_target_harness.cpp
#     LIBS    doom_idlib   # or other libs
#   )
