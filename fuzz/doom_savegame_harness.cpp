// Fuzz Doom 3 BFG's savegame file codec. This exercises the in-memory savegame
// file container plus the pipelined compressed read/write path used for saves.

#include <algorithm>
#include <cstddef>
#include <cstdint>

#ifdef __has_include
#  if __has_include("idlib/precompiled.h")
#    include "idlib/precompiled.h"
#    include "framework/File_SaveGame.h"
#    define HAVE_SAVEGAME_FILE 1
#  endif
#endif

#ifdef HAVE_SAVEGAME_FILE
extern idCVar sgf_threads;
extern idCVar sgf_checksums;
extern idCVar sgf_testCorruption;
extern idCVar sgf_windowBits;

class idFuzzCVarAccess : public idCVar {
public:
    void ForceValue(const char *stringValue, int intValue, float floatValue) {
        value = stringValue;
        integerValue = intValue;
        this->floatValue = floatValue;
        internalVar = this;
    }
};

static void InitSavegameCVars() {
    reinterpret_cast<idFuzzCVarAccess *>(&sgf_threads)->ForceValue("0", 0, 0.0f);
    reinterpret_cast<idFuzzCVarAccess *>(&sgf_checksums)->ForceValue("1", 1, 1.0f);
    reinterpret_cast<idFuzzCVarAccess *>(&sgf_testCorruption)->ForceValue("-1", -1, -1.0f);
    reinterpret_cast<idFuzzCVarAccess *>(&sgf_windowBits)->ForceValue("-15", -15, -15.0f);
}
#endif

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (data == nullptr || size == 0) {
        return 0;
    }

#ifdef HAVE_SAVEGAME_FILE
    InitSavegameCVars();

    const char *bytes = reinterpret_cast<const char *>(data);
    const int inputLen = static_cast<int>(std::min<size_t>(size, 16 << 10));

    idFile_SaveGame rawInput("fuzz.save");
    rawInput.SetData(bytes, inputLen);
    rawInput.type = SAVEGAMEFILE_BINARY | SAVEGAMEFILE_COMPRESSED;
    rawInput.error = false;

    char scratch[4096];
    rawInput.Read(scratch, static_cast<int>(std::min<size_t>(sizeof(scratch), size)));
    rawInput.Seek(0, FS_SEEK_SET);

    idStr maybeString;
    rawInput.ReadString(maybeString);
    rawInput.Seek(0, FS_SEEK_SET);

    idFile_SaveGamePipelined *compressedInput = new idFile_SaveGamePipelined();
    if (compressedInput->OpenForReading(&rawInput)) {
        compressedInput->Read(scratch, sizeof(scratch));
        compressedInput->Finish();
    }
    compressedInput->~idFile_SaveGamePipelined();
    Mem_Free(compressedInput);

    char *outputStorage = static_cast<char *>(Mem_Alloc(64 << 10, TAG_SAVEGAMES));
    idFile_Memory compressedOutput("roundtrip.save", outputStorage, 64 << 10);
    idFile_SaveGamePipelined *writer = new idFile_SaveGamePipelined();
    if (writer->OpenForWriting(&compressedOutput)) {
        writer->Write(bytes, inputLen);
        writer->Finish();
    }
    writer->~idFile_SaveGamePipelined();
    Mem_Free(writer);
    Mem_Free(outputStorage);
#endif

    return 0;
}
