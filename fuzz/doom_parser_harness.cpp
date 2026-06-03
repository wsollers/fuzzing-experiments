// fuzz/doom_parser_harness.cpp
//
// Fuzz the idLexer / idParser from Doom 3 BFG idLib.
// OpenGrep rules flag unsafe sscanf/sprintf patterns in the parser;
// this harness drives those code paths with arbitrary input.

#include <cstddef>
#include <cstdint>
#include <cstring>
#include <algorithm>

#ifdef __has_include
#  if __has_include("idlib/LexerNG.h")
#    include "idlib/LexerNG.h"
#    include "idlib/Token.h"
#    define HAVE_LEXER 1
#  elif __has_include("idlib/Lexer.h")
#    include "idlib/Lexer.h"
#    include "idlib/Token.h"
#    define HAVE_LEXER 1
#  endif
#endif

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size == 0) return 0;

#ifdef HAVE_LEXER
    char buf[8192];
    size_t len = std::min(size, sizeof(buf) - 1);
    memcpy(buf, data, len);
    buf[len] = '\0';

    idLexer lexer;
    lexer.LoadMemory(buf, static_cast<int>(len), "<fuzz_input>");

    idToken token;
    int tokens_read = 0;
    // Drain up to 1024 tokens to bound CPU per input
    while (tokens_read < 1024 && lexer.ReadToken(&token)) {
        ++tokens_read;
    }
#endif
    return 0;
}
