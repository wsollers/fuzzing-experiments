# cmake/clang_fuzzing.cmake
# Registers a LibFuzzer harness target.
# Supports three modes:
#   MSVC native    — /fsanitize=fuzzer  /fsanitize=address  (VS 2022 17.0+)
#   clang-cl       — -fsanitize=fuzzer  -fsanitize=address  (LLVM for Windows)
#   Clang Linux    — -fsanitize=fuzzer  -fsanitize=address  (standard)
#
# Usage:
#   add_fuzzer_target(my_fuzzer SOURCES harness.cpp LIBS some_lib)

function(add_fuzzer_target name)
  cmake_parse_arguments(FUZZ "" "" "SOURCES;LIBS" ${ARGN})

  if(NOT FUZZ_SOURCES)
    message(FATAL_ERROR "add_fuzzer_target(${name}): SOURCES required")
  endif()

  add_executable(${name} ${FUZZ_SOURCES})

  # ── Detect compiler personality ─────────────────────────────────────────────
  if(MSVC AND NOT CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
    set(IS_MSVC_NATIVE TRUE)
  else()
    set(IS_MSVC_NATIVE FALSE)
  endif()

  if(CMAKE_CXX_COMPILER_ID STREQUAL "Clang" AND WIN32)
    set(IS_CLANG_CL TRUE)
  else()
    set(IS_CLANG_CL FALSE)
  endif()

  # ── Compiler flags ───────────────────────────────────────────────────────────
  if(IS_MSVC_NATIVE)
    # MSVC native LibFuzzer support (VS 2022 17.0+)
    # /fsanitize=fuzzer implies coverage instrumentation automatically
    target_compile_options(${name} PRIVATE
      /fsanitize=fuzzer
      /fsanitize=address
      /Zi                      # debug info — needed for good crash reports
      /Od                      # debug optimisation level
      /EHa                     # async exceptions — required with ASan on MSVC
    )
    target_link_options(${name} PRIVATE
      /fsanitize=fuzzer
      /fsanitize=address
      /DEBUG
    )
    # MSVC fuzzer needs _ITERATOR_DEBUG_LEVEL=0 to avoid mismatched runtime
    target_compile_definitions(${name} PRIVATE _ITERATOR_DEBUG_LEVEL=0)

  elseif(IS_CLANG_CL)
    # clang-cl on Windows — uses clang flags but MSVC ABI linker
    target_compile_options(${name} PRIVATE
      -fsanitize=fuzzer
      -fsanitize=address
      -fprofile-instr-generate
      -fcoverage-mapping
      -fno-omit-frame-pointer
      -g
      -O1
    )
    target_link_options(${name} PRIVATE
      -fsanitize=fuzzer
      -fsanitize=address
      -fprofile-instr-generate
    )

  else()
    # Clang on Linux / macOS
    target_compile_options(${name} PRIVATE
      -fsanitize=fuzzer
      -fsanitize=address
      -fsanitize=undefined
      -fprofile-instr-generate
      -fcoverage-mapping
      -fno-omit-frame-pointer
      -g
      -O1
    )
    target_link_options(${name} PRIVATE
      -fsanitize=fuzzer
      -fsanitize=address
      -fsanitize=undefined
      -fprofile-instr-generate
    )
  endif()

  if(FUZZ_LIBS)
    target_link_libraries(${name} PRIVATE ${FUZZ_LIBS})
  endif()

  apply_sanitizer_flags(${name})

  # Output all fuzzer binaries to build/fuzzers/ for easy scripting
  set_target_properties(${name} PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/fuzzers"
  )
endfunction()
