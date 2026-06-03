# cmake/clang_fuzzing.cmake
# Registers a LibFuzzer harness target.
# Supports three modes:
#   MSVC native  -- /fsanitize=fuzzer /fsanitize=address  (VS 2022 17.0+)
#   clang-cl     -- compile with -fsanitize=*, link clang runtime .lib files
#   Clang Linux  -- -fsanitize=fuzzer -fsanitize=address  (standard)
#
# Usage:
#   add_fuzzer_target(my_fuzzer SOURCES harness.cpp LIBS some_lib)

# Helper: find the clang resource directory for a given compiler executable.
# Returns the path in the variable named by OUT_VAR.
function(_find_clang_resource_dir compiler out_var)
  execute_process(
    COMMAND "${compiler}" --print-resource-dir
    OUTPUT_VARIABLE _res
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_QUIET
  )
  set(${out_var} "${_res}" PARENT_SCOPE)
endfunction()

function(add_fuzzer_target name)
  cmake_parse_arguments(FUZZ "" "" "SOURCES;LIBS" ${ARGN})

  if(NOT FUZZ_SOURCES)
    message(FATAL_ERROR "add_fuzzer_target(${name}): SOURCES required")
  endif()

  add_executable(${name} ${FUZZ_SOURCES})

  # -- Detect compiler personality ---------------------------------------------
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

  # -- Compiler flags ----------------------------------------------------------
  if(IS_MSVC_NATIVE)
    # MSVC native LibFuzzer (VS 2022 17.0+): /fsanitize= flags work end-to-end
    target_compile_options(${name} PRIVATE
      /fsanitize=fuzzer
      /fsanitize=address
      /Zi
      /Od
      /EHa
    )
    target_link_options(${name} PRIVATE
      /fsanitize=fuzzer
      /fsanitize=address
      /DEBUG
    )
    target_compile_definitions(${name} PRIVATE _ITERATOR_DEBUG_LEVEL=0)

  elseif(IS_CLANG_CL)
    # clang-cl: compile flags work fine; lld-link does NOT understand
    # -fsanitize= flags so we must link the runtime .lib files explicitly.
    target_compile_options(${name} PRIVATE
      -fsanitize=fuzzer
      -fsanitize=address
      -fsanitize=undefined
      -fprofile-instr-generate
      -fcoverage-mapping
      /Oy-
      -g
      -O1
    )
    add_clang_windows_runtime(${name} fuzzer)
    add_clang_windows_runtime(${name} fuzzer_interceptors)

  else()
    # Clang on Linux / macOS -- standard flags work end-to-end
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

  set_target_properties(${name} PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/fuzzers"
  )
endfunction()
