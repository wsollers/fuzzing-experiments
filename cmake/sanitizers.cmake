# cmake/sanitizers.cmake
# Applies sanitizer flags to a target based on build options.

function(apply_sanitizer_flags target)
  set(SAN_FLAGS "")

  if(ENABLE_ASAN)
    list(APPEND SAN_FLAGS -fsanitize=address -fno-omit-frame-pointer)
  endif()

  if(ENABLE_UBSAN)
    list(APPEND SAN_FLAGS
      -fsanitize=undefined
      -fsanitize=integer
      -fsanitize=nullability
      -fno-sanitize-recover=all
    )
  endif()

  if(ENABLE_MSAN)
    if(ENABLE_ASAN)
      message(FATAL_ERROR "MSan and ASan cannot be combined.")
    endif()
    list(APPEND SAN_FLAGS -fsanitize=memory -fsanitize-memory-track-origins=2)
  endif()

  if(ENABLE_COVERAGE)
    list(APPEND SAN_FLAGS
      -fprofile-instr-generate
      -fcoverage-mapping
    )
  endif()

  if(SAN_FLAGS)
    target_compile_options(${target} PRIVATE ${SAN_FLAGS})
    target_link_options(${target} PRIVATE ${SAN_FLAGS})
  endif()
endfunction()
