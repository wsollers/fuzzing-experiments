// fuzz/harness_template.cpp
//
// Copy this file to create a new LibFuzzer harness.
// Replace MY_TARGET with a descriptive name and implement the body.
//
// Build with:  cmake -DENABLE_FUZZING=ON -DENABLE_ASAN=ON ..
// Run with:    ./build/fuzzers/fuzz_my_target seeds/my_target/

#include <cstddef>
#include <cstdint>
#include <cstring>

// Include the headers for the code under test:
// #include "idlib/Str.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size == 0) return 0;

    // ---- YOUR FUZZING LOGIC HERE ----
    //
    // Example: feed raw bytes as a null-terminated string to a parser.
    //
    //   char buf[4096];
    //   size_t copy_len = std::min(size, sizeof(buf) - 1);
    //   memcpy(buf, data, copy_len);
    //   buf[copy_len] = '\0';
    //   idStr str(buf);
    //   str.ToLower();
    //
    // ---------------------------------

    return 0;
}
