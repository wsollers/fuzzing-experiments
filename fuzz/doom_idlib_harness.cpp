// fuzz/doom_idlib_harness.cpp
//
// Fuzz the idLib string and math utilities from Doom 3 BFG.
// NOTE: precompiled.h MUST be first -- it defines ID_INLINE, uint8, uint32,
// byte, BIT, and all other idLib primitive types before any other header.

#include <cstddef>
#include <cstdint>
#include <cstring>
#include <algorithm>

#ifdef __has_include
#  if __has_include("precompiled.h")
#    include "precompiled.h"
#    if __has_include("idlib/Str.h")
#      include "idlib/Str.h"
#      include "idlib/math/Math.h"
#      include "idlib/math/Vector.h"
#      define HAVE_IDLIB 1
#    endif
#  endif
#endif

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size < 2) return 0;

#ifdef HAVE_IDLIB
    // -- String fuzzing -------------------------------------------------------
    char buf[2048];
    size_t len = std::min(size, sizeof(buf) - 1);
    memcpy(buf, data, len);
    buf[len] = '\0';

    idStr s(buf);
    s.ToLower();
    s.StripTrailingWhitespace();
    (void)s.Length();

    if (s.Length() > 0) {
        volatile char c = s[0];
        (void)c;
    }

    idStr t("prefix_");
    t += s;

    // -- Math fuzzing ---------------------------------------------------------
    if (size >= sizeof(float)) {
        float f;
        memcpy(&f, data, sizeof(float));
        volatile float sq = idMath::Sqrt(f >= 0 ? f : -f);
        volatile float si = idMath::Sin(f);
        volatile float co = idMath::Cos(f);
        (void)sq; (void)si; (void)co;
    }

    if (size >= sizeof(idVec3)) {
        idVec3 v;
        memcpy(&v, data, sizeof(idVec3));
        volatile float vlen = v.Length();
        (void)vlen;
        if (v.Length() > 0.0001f) v.Normalize();
    }
#endif
    return 0;
}
