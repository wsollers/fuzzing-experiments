// fuzz/doom_idlib_harness.cpp
//
// Fuzz the idLib string and math utilities from Doom 3 BFG.
// CodeQL path_conditions.ql highlights which branches in idStr::operator[]
// and idMath::* are uncovered; this harness is structured to exercise them.

#include <cstddef>
#include <cstdint>
#include <cstring>
#include <algorithm>

// idLib headers (present after clone_doom.sh)
#ifdef __has_include
#  if __has_include("idlib/Str.h")
#    include "idlib/Str.h"
#    include "idlib/math/Math.h"
#    include "idlib/math/Vector.h"
#    define HAVE_IDLIB 1
#  endif
#endif

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size < 2) return 0;

#ifdef HAVE_IDLIB
    // ── String fuzzing ───────────────────────────────────────────────
    char buf[2048];
    size_t len = std::min(size, sizeof(buf) - 1);
    memcpy(buf, data, len);
    buf[len] = '\0';

    idStr s(buf);
    s.ToLower();
    s.StripLeadingWhitespace();
    s.StripTrailingWhitespace();
    (void)s.Length();
    (void)s.Checksum();

    // Index access (path exercised by CodeQL buffer_access.ql)
    if (s.Length() > 0) {
        volatile char c = s[0];
        (void)c;
    }

    // Concatenation path
    idStr t("prefix_");
    t += s;

    // Format path
    idStr formatted;
    formatted = idStr::Format("%s_%d", buf, (int)size);

    // ── Math fuzzing ───────────────────────────────────────────────
    if (size >= sizeof(float)) {
        float f;
        memcpy(&f, data, sizeof(float));
        volatile float sq = idMath::Sqrt(f >= 0 ? f : -f);  // UBSan: ensure non-neg
        volatile float si = idMath::Sin(f);
        volatile float co = idMath::Cos(f);
        (void)sq; (void)si; (void)co;
    }

    if (size >= sizeof(idVec3)) {
        idVec3 v;
        memcpy(&v, data, sizeof(idVec3));
        volatile float len2 = v.Length();
        (void)len2;
        if (v.Length() > 0.0001f) v.Normalize();
    }
#endif
    return 0;
}
