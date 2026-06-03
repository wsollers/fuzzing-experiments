// Minimal headless implementation of idRestoreGame's scalar/container readers
// for fuzzing savegame rehydration without linking the full d3xp game module.

#include "idlib/precompiled.h"
#include "d3xp/Game_local.h"

idRestoreGame::idRestoreGame(idFile *savefile, idFile *stringTableFile, int saveVersion) {
    file = savefile;
    stringFile = stringTableFile;
    version = saveVersion;
    stringTableOffset = 0;
}

idRestoreGame::~idRestoreGame() {
}

void idRestoreGame::Read(void *buffer, int len) {
    file->Read(buffer, len);
}

void idRestoreGame::ReadInt(int &value) {
    file->ReadBig(value);
}

void idRestoreGame::ReadJoint(jointHandle_t &value) {
    file->ReadBig((int &)value);
}

void idRestoreGame::ReadShort(short &value) {
    file->ReadBig(value);
}

void idRestoreGame::ReadByte(byte &value) {
    file->Read(&value, sizeof(value));
}

void idRestoreGame::ReadSignedChar(signed char &value) {
    file->Read(&value, sizeof(value));
}

void idRestoreGame::ReadFloat(float &value) {
    file->ReadBig(value);
}

void idRestoreGame::ReadBool(bool &value) {
    file->ReadBig(value);
}

void idRestoreGame::ReadString(idStr &string) {
    string.Empty();

    int offset = -1;
    ReadInt(offset);
    if (offset < 0) {
        return;
    }

    const int stringFileLength = stringFile->Length();
    if (offset > stringFileLength - static_cast<int>(sizeof(int))) {
        return;
    }

    stringFile->Seek(offset, FS_SEEK_SET);
    int len = -1;
    stringFile->ReadInt(len);
    if (len < 0 || len > 4096 || len > stringFileLength - stringFile->Tell()) {
        return;
    }

    string.Fill(' ', len);
    stringFile->Read(&string[0], len);
}

void idRestoreGame::ReadVec2(idVec2 &vec) {
    file->ReadBig(vec);
}

void idRestoreGame::ReadVec3(idVec3 &vec) {
    file->ReadBig(vec);
}

void idRestoreGame::ReadVec4(idVec4 &vec) {
    file->ReadBig(vec);
}

void idRestoreGame::ReadVec6(idVec6 &vec) {
    file->ReadBig(vec);
}

void idRestoreGame::ReadBounds(idBounds &bounds) {
    file->ReadBig(bounds);
}

void idRestoreGame::ReadMat3(idMat3 &mat) {
    file->ReadBig(mat);
}

void idRestoreGame::ReadAngles(idAngles &angles) {
    file->ReadBig(angles);
}

void idRestoreGame::ReadDict(idDict *dict) {
    int num = 0;
    idStr key;
    idStr value;

    ReadInt(num);
    if (num < 0) {
        return;
    }

    if (num > 128) {
        num = 128;
    }
    dict->Clear();
    for (int i = 0; i < num; i++) {
        ReadString(key);
        ReadString(value);
        dict->Set(key, value);
    }
}

void idRestoreGame::ReadUsercmd(usercmd_t &usercmd) {
    ReadByte(usercmd.buttons);
    ReadSignedChar(usercmd.forwardmove);
    ReadSignedChar(usercmd.rightmove);
    ReadShort(usercmd.angles[0]);
    ReadShort(usercmd.angles[1]);
    ReadShort(usercmd.angles[2]);
    ReadShort(usercmd.mx);
    ReadShort(usercmd.my);
    ReadByte(usercmd.impulse);
    ReadByte(usercmd.impulseSequence);
}
