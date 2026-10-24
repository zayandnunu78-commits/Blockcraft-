#include <SDL.h>
#include <winrt/Windows.ApplicationModel.h>
#include <winrt/Windows.Storage.h>

#include <windows.h>

#include <string>

extern "C" int SDL_main(int argc, char **argv);

namespace
{
int runLove(int, char **)
{
    const auto installed = winrt::Windows::ApplicationModel::Package::Current()
        .InstalledLocation().Path();
    std::string gamePath = winrt::to_string(installed + L"\\blockcraft.love");

    char executable[] = "BlockcraftUWP";
    char fused[] = "--fused";
    char *loveArgv[] = {executable, gamePath.data(), fused, nullptr};
    return SDL_main(3, loveArgv);
}
}

int CALLBACK WinMain(HINSTANCE, HINSTANCE, LPSTR, int)
{
    SDL_SetHint(SDL_HINT_WINRT_HANDLE_BACK_BUTTON, "1");
    return SDL_WinRTRunApp(runLove, nullptr);
}
