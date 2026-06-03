# cmake/sanitizers.cmake
# Applies sanitizer flags to a target.
# Handles three compiler personalities:
#   - Clang/GCC on Linux/Mac  (-fsanitize=...)
#   - clang-cl on Windows     (-fsanitize=... passed via /clang: or directly)
#   - MSVC on Windows         (/fsanitize=address  /fsanitize=fuzzer)

function(get_clang_windows_runtime_dir out_var)
  if(NOT WIN32 OR NOT CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
    set(${out_var} "" PARENT_SCOPE)
    return()
  endif()

  execute_process(
    COMMAND "${CMAKE_CXX_COMPILER}" --print-resource-dir
    OUTPUT_VARIABLE CLANG_RESOURCE_DIR
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_QUIET
  )

  set(CLANG_RUNTIME_DIR "${CLANG_RESOURCE_DIR}/lib/windows")
  if(NOT EXISTS "${CLANG_RUNTIME_DIR}")
    message(FATAL_ERROR
      "Could not locate clang-cl runtime libraries at ${CLANG_RUNTIME_DIR}. "
      "Install LLVM for Windows or the Visual Studio LLVM toolset."
    )
  endif()

  set(${out_var} "${CLANG_RUNTIME_DIR}" PARENT_SCOPE)
endfunction()

function(add_clang_windows_runtime target runtime_name)
  get_clang_windows_runtime_dir(CLANG_RUNTIME_DIR)
  if(CMAKE_SIZEOF_VOID_P EQUAL 8)
    set(CLANG_ARCH "x86_64")
  else()
    set(CLANG_ARCH "i386")
  endif()

  set(RUNTIME_LIB "${CLANG_RUNTIME_DIR}/clang_rt.${runtime_name}-${CLANG_ARCH}.lib")
  if(NOT EXISTS "${RUNTIME_LIB}")
    message(FATAL_ERROR "Missing clang-cl runtime library: ${RUNTIME_LIB}")
  endif()

  target_link_libraries(${target} PRIVATE "${RUNTIME_LIB}")
endfunction()

function(apply_sanitizer_flags target)

  # ── Detect compiler personality ────────────────────────────────────────────
  if(MSVC AND NOT CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
    set(IS_MSVC_NATIVE TRUE)
  else()
    set(IS_MSVC_NATIVE FALSE)
  endif()

  # clang-cl reports MSVC ABI but CMAKE_CXX_COMPILER_ID == "Clang"
  if(CMAKE_CXX_COMPILER_ID STREQUAL "Clang" AND WIN32)
    set(IS_CLANG_CL TRUE)
  else()
    set(IS_CLANG_CL FALSE)
  endif()

  set(COMPILE_FLAGS "")
  set(LINK_FLAGS "")

  # ── AddressSanitizer ────────────────────────────────────────────────────────
  if(ENABLE_ASAN)
    if(IS_MSVC_NATIVE)
      # MSVC ASan: compile flag only; linker picks up the runtime automatically
      list(APPEND COMPILE_FLAGS /fsanitize=address)
    elseif(IS_CLANG_CL)
      list(APPEND COMPILE_FLAGS -fsanitize=address /Oy-)
      add_clang_windows_runtime(${target} asan)
      add_clang_windows_runtime(${target} asan_cxx)
      add_clang_windows_runtime(${target} asan-preinit)
    else()
      list(APPEND COMPILE_FLAGS -fsanitize=address -fno-omit-frame-pointer)
      list(APPEND LINK_FLAGS    -fsanitize=address)
    endif()
  endif()

  # ── UndefinedBehaviorSanitizer ──────────────────────────────────────────────
  # UBSan is not supported by MSVC native; clang-cl supports a subset
  if(ENABLE_UBSAN)
    if(IS_MSVC_NATIVE)
      message(STATUS "[sanitizers] UBSan not supported by MSVC; skipping.")
    elseif(IS_CLANG_CL)
      # clang-cl supports -fsanitize=undefined but not the sub-sanitizers
      list(APPEND COMPILE_FLAGS -fsanitize=undefined)
      add_clang_windows_runtime(${target} ubsan_standalone)
      add_clang_windows_runtime(${target} ubsan_standalone_cxx)
    else()
      list(APPEND COMPILE_FLAGS
        -fsanitize=undefined
        -fsanitize=integer
        -fsanitize=nullability
        -fno-sanitize-recover=all
      )
      list(APPEND LINK_FLAGS
        -fsanitize=undefined
      )
    endif()
  endif()

  # ── MemorySanitizer ─────────────────────────────────────────────────────────
  if(ENABLE_MSAN)
    if(WIN32)
      message(STATUS "[sanitizers] MSan not supported on Windows; skipping.")
    else()
      if(ENABLE_ASAN)
        message(FATAL_ERROR "MSan and ASan cannot be combined.")
      endif()
      list(APPEND COMPILE_FLAGS -fsanitize=memory -fsanitize-memory-track-origins=2)
      list(APPEND LINK_FLAGS    -fsanitize=memory)
    endif()
  endif()

  # ── Coverage instrumentation ────────────────────────────────────────────────
  if(ENABLE_COVERAGE)
    if(IS_MSVC_NATIVE)
      # MSVC coverage via /profile; separate from clang coverage maps
      list(APPEND COMPILE_FLAGS /Zi)
    else()
      list(APPEND COMPILE_FLAGS
        -fprofile-instr-generate
        -fcoverage-mapping
      )
      if(IS_CLANG_CL)
        add_clang_windows_runtime(${target} profile)
      else()
        list(APPEND LINK_FLAGS -fprofile-instr-generate)
      endif()
    endif()
  endif()

  # ── Apply ───────────────────────────────────────────────────────────────────
  if(COMPILE_FLAGS)
    target_compile_options(${target} PRIVATE ${COMPILE_FLAGS})
  endif()
  if(LINK_FLAGS)
    target_link_options(${target} PRIVATE ${LINK_FLAGS})
  endif()

endfunction()
