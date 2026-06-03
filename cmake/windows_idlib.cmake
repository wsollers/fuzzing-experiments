# cmake/windows_idlib.cmake
# Windows-specific compile definitions and flag overrides for Doom 3 BFG idLib.
# On Windows, _WIN32 is already defined by the compiler so idLib's platform
# detection works naturally — but we still need to suppress warnings and
# handle MSVC vs clang-cl differences.

function(apply_windows_idlib_flags target)

  if(MSVC AND NOT CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
    # MSVC native
    target_compile_options(${target} PRIVATE
      /W0                  # suppress all warnings for third-party code
      /EHa                 # async exception handling
      /MP                  # parallel compilation
      /wd4996              # 'deprecated' CRT function warnings
      /wd4244              # conversion / possible loss of data
      /wd4267              # size_t -> int conversion
      /wd4305              # truncation double -> float
      /wd4018              # signed/unsigned mismatch
      /wd4800              # int -> bool performance warning
    )
    target_compile_definitions(${target} PRIVATE
      _CRT_SECURE_NO_WARNINGS
      _CRT_NONSTDC_NO_WARNINGS
      NOMINMAX              # prevent windows.h min/max macros stomping std::
      WIN32_LEAN_AND_MEAN
    )
  else()
    # clang-cl or Clang targeting Windows
    target_compile_options(${target} PRIVATE
      -Wno-everything       # third-party code — silence all warnings
    )
    target_compile_definitions(${target} PRIVATE
      _CRT_SECURE_NO_WARNINGS
      NOMINMAX
      WIN32_LEAN_AND_MEAN
    )
  endif()

endfunction()
