// Fuzz Doom 3 BFG's savegame rehydration reader. This targets the
// idRestoreGame layer that turns savegame byte streams back into game values
// and object references, without booting maps or rendering state.

#include <algorithm>
#include <cstdint>

#include "idlib/precompiled.h"
#include "framework/File_SaveGame.h"
#include "d3xp/Game_local.h"

static void ExercisePrimitiveRestoreReads(idRestoreGame &restore) {
    int intValue = 0;
    short shortValue = 0;
    byte byteValue = 0;
    signed char signedCharValue = 0;
    float floatValue = 0.0f;
    bool boolValue = false;
    idStr stringValue;
    idVec2 vec2Value;
    idVec3 vec3Value;
    idVec4 vec4Value;
    idVec6 vec6Value;
    idBounds boundsValue;
    idMat3 mat3Value;
    idAngles anglesValue;
    usercmd_t usercmdValue;
    idDict dictValue;

    restore.ReadInt(intValue);
    restore.ReadShort(shortValue);
    restore.ReadByte(byteValue);
    restore.ReadSignedChar(signedCharValue);
    restore.ReadFloat(floatValue);
    restore.ReadBool(boolValue);
    restore.ReadString(stringValue);
    restore.ReadVec2(vec2Value);
    restore.ReadVec3(vec3Value);
    restore.ReadVec4(vec4Value);
    restore.ReadVec6(vec6Value);
    restore.ReadBounds(boundsValue);
    restore.ReadMat3(mat3Value);
    restore.ReadAngles(anglesValue);
    restore.ReadUsercmd(usercmdValue);
    restore.ReadDict(&dictValue);
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (data == NULL || size < 8) {
        return 0;
    }

    const size_t cappedSize = std::min<size_t>(size, 128 << 10);
    const uint8_t splitByte = data[0];
    const size_t split = 1 + (static_cast<size_t>(splitByte) % (cappedSize - 1));
    const size_t gameStateSize = split;
    const size_t stringTableSize = cappedSize - split;

    idFile_SaveGame gameState("fuzz_gamedata.save");
    gameState.SetData(reinterpret_cast<const char *>(data), static_cast<int>(gameStateSize));
    gameState.type = SAVEGAMEFILE_BINARY;
    gameState.error = false;
    gameState.MakeReadOnly();

    idFile_SaveGame stringTable("fuzz_gamedata.strings");
    stringTable.SetData(reinterpret_cast<const char *>(data + split), static_cast<int>(stringTableSize));
    stringTable.type = SAVEGAMEFILE_BINARY;
    stringTable.error = false;
    stringTable.MakeReadOnly();

    idRestoreGame restore(&gameState, &stringTable, 0);
    ExercisePrimitiveRestoreReads(restore);

    return 0;
}
