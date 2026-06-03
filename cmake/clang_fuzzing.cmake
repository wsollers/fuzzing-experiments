# cmake/clang_fuzzing.cmake
# Registers a LibFuzzer harness target with all required flags.
#
# Usage:
#   add_fuzzer_target(my_fuzzer SOURCES harness.cpp LIBS some_lib)

function(add_fuzzer_target name)
  cmake_parse_arguments(FUZZ "" "" "SOURCES;LIBS" ${ARGN})

  if(NOT FUZZ_SOURCES)
    message(FATAL_ERROR "add_fuzzer_target(${name}): SOURCES required")
  endif()

  add_executable(${name} ${FUZZ_SOURCES})

  target_compile_options(${name} PRIVATE
    -fsanitize=fuzzer
    -fsanitize=address
    -fsanitize=undefined
    -fprofile-instr-generate
    -fcoverage-mapping
    -fno-omit-frame-pointer
    -g
    -O1                    # Optimise enough to expose bugs, not so much as to hide them
  )

  target_link_options(${name} PRIVATE
    -fsanitize=fuzzer
    -fsanitize=address
    -fsanitize=undefined
    -fprofile-instr-generate
  )

  if(FUZZ_LIBS)
    target_link_libraries(${name} PRIVATE ${FUZZ_LIBS})
  endif()

  apply_sanitizer_flags(${name})

  # Install fuzzer binary into build/fuzzers/ for easy scripting
  set_target_properties(${name} PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/fuzzers"
  )
endfunction()
