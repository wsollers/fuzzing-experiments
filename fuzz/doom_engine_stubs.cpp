// Minimal engine symbols needed when linking idLib outside the full Doom 3 BFG
// executable. Keep these inert: fuzz harnesses should not perform real engine IO.

#include "idlib/precompiled.h"
#include "framework/Common.h"
#include "framework/CVarSystem.h"

class idFileSystem;

class idFuzzCommon : public idCommon {
public:
    void Init(int argc, const char * const * argv, const char *cmdline) override {}
    void Shutdown() override {}
    bool IsShuttingDown() const override { return false; }
    void CreateMainMenu() override {}
    void Quit() override {}
    bool IsInitialized() const override { return true; }
    void Frame() override {}
    void UpdateScreen(bool captureToImage) override {}
    void UpdateLevelLoadPacifier() override {}
    void StartupVariable(const char *match) override {}
    void BeginRedirect(char *buffer, int buffersize, void (*flush)(const char *)) override {}
    void EndRedirect() override {}
    void SetRefreshOnPrint(bool set) override {}
    void Printf(const char *fmt, ...) override {}
    void VPrintf(const char *fmt, va_list arg) override {}
    void DPrintf(const char *fmt, ...) override {}
    void Warning(const char *fmt, ...) override {}
    void DWarning(const char *fmt, ...) override {}
    void PrintWarnings() override {}
    void ClearWarnings(const char *reason) override {}
    void Error(const char *fmt, ...) override {}
    void FatalError(const char *fmt, ...) override {}
    const char * KeysFromBinding(const char *bind) override { return ""; }
    const char * BindingFromKey(const char *key) override { return ""; }
    int ButtonState(int key) override { return 0; }
    int KeyState(int key) override { return 0; }
    bool IsMultiplayer() override { return false; }
    bool IsServer() override { return false; }
    bool IsClient() override { return false; }
    bool GetConsoleUsed() override { return false; }
    int GetSnapRate() override { return 0; }
    void NetReceiveReliable(int peer, int type, idBitMsg &msg) override {}
    void NetReceiveSnapshot(idSnapShot &ss) override {}
    void NetReceiveUsercmds(int peer, idBitMsg &msg) override {}
    bool ProcessEvent(const sysEvent_t *event) override { return false; }
    bool LoadGame(const char *saveName) override { return false; }
    bool SaveGame(const char *saveName) override { return false; }
    idDemoFile * ReadDemo() override { return NULL; }
    idDemoFile * WriteDemo() override { return NULL; }
    idGame * Game() override { return NULL; }
    idRenderWorld * RW() override { return NULL; }
    idSoundWorld * SW() override { return NULL; }
    idSoundWorld * MenuSW() override { return NULL; }
    idSession * Session() override { return NULL; }
    idCommonDialog & Dialog() override {
        static idCommonDialog *dialog = NULL;
        return *dialog;
    }
    void OnSaveCompleted(idSaveLoadParms &parms) override {}
    void OnLoadCompleted(idSaveLoadParms &parms) override {}
    void OnLoadFilesCompleted(idSaveLoadParms &parms) override {}
    void OnEnumerationCompleted(idSaveLoadParms &parms) override {}
    void OnDeleteCompleted(idSaveLoadParms &parms) override {}
    void TriggerScreenWipe(const char *_wipeMaterial, bool hold) override {}
    void OnStartHosting(idMatchParameters &parms) override {}
    int GetGameFrame() override { return 0; }
    void LaunchExternalTitle(int titleIndex, int device, const lobbyConnectInfo_t * const connectInfo) override {}
    void InitializeMPMapsModes() override {}
    const idStrList & GetModeList() const override {
        static idStrList list;
        return list;
    }
    const idStrList & GetModeDisplayList() const override {
        static idStrList list;
        return list;
    }
    const idList<mpMap_t> & GetMapList() const override {
        static idList<mpMap_t> list;
        return list;
    }
    void ResetPlayerInput(int playerIndex) override {}
    bool JapaneseCensorship() const override { return false; }
    void QueueShowShell() override {}
    currentGame_t GetCurrentGame() const override { return DOOM3_BFG; }
    void SwitchToGame(currentGame_t newGame) override {}
};

static idFuzzCommon fuzzCommon;

idCVar * idCVar::staticVars = NULL;
idCVarSystem * cvarSystem = NULL;
idFileSystem * fileSystem = NULL;
idCommon * common = &fuzzCommon;

struct idFuzzGlobals {
    idFuzzGlobals() {
        idLib::common = &fuzzCommon;
    }
};

static idFuzzGlobals fuzzGlobals;

int Sys_Milliseconds() {
    static int fuzzTimeMs = 0;
    return fuzzTimeMs++;
}

uint64 Sys_Microseconds() {
    return static_cast<uint64>(Sys_Milliseconds()) * 1000;
}

ID_TIME_T Sys_FileTimeStamp(idFileHandle fp) {
    (void)fp;
    return 0;
}
