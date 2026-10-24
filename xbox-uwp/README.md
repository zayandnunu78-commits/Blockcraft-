# Blockcraft 1 Xbox UWP host scaffold

This directory is the application layer around the bundled `love-xbox-uwp-main` engine. It is intentionally separate from the Blockcraft game source and from the production multiplayer server.

## Current status

This is an **unbuilt scaffold**. It has not been compiled, signed, installed, or tested on Xbox One Developer Mode. The current Linux sandbox cannot build it because Visual Studio/MSVC, the Windows SDK, CMake, PowerShell, SDL2 UWP libraries, ANGLE/runtime DLLs, and MSIX tooling are unavailable.

The scaffold contains:

- `app/main.cpp`: WinRT host that launches the fused `blockcraft.love` payload through `SDL_WinRTRunApp` and `SDL_main`.
- `Package.appxmanifest.in`: package identity, visual assets, and network/code-generation capabilities.
- `CMakeLists.txt`: x64 WindowsStore host build, fused payload creation, dependency checks, and Visual Studio deployment content.
- `CMakePresets.json`: Visual Studio 17 2022 x64 UWP presets.
- `Assets/`: package asset directory. Replace the placeholders with final Blockcraft artwork before distribution.

## Windows prerequisites

Install Visual Studio 2022 with UWP development, MSVC v143 x64 tools, Windows SDK 10.0.19041 or newer, CMake 3.24+, PowerShell, Git, and packaging/signing tools. Build an x64 UWP SDL2 installation compatible with the engine fork. Build the LÖVE fork first with LuaJIT and ANGLE, then point `BLOCKCRAFT_LOVE_BUILD` at its `RelWithDebInfo` or `Release` output.

The host expects these engine artifacts:

- `love.dll`
- `lua51.dll`
- `lovestatic.lib`
- `liblove.lib`
- `lua51.lib`

and these SDL artifacts:

- `include/SDL2/SDL.h`
- `lib/SDL2.lib`
- `SDL2.dll` staged into the package by the Windows packaging project.

## Configure and build

From a Visual Studio Developer PowerShell, first build the engine from its source directory using `platform/uwp/README.md`. Then configure the host:

```powershell
cd xbox-uwp
cmake --preset uwp-relwithdebinfo `
  -DBLOCKCRAFT_SDL_ROOT=C:/path/to/sdl2-install `
  -DBLOCKCRAFT_LOVE_BUILD=C:/path/to/love/build/RelWithDebInfo
cmake --build --preset uwp-relwithdebinfo
```

The generated Visual Studio package still needs the complete SDL2, ANGLE, vcpkg runtime DLL set, package signing, and Device Portal installation. Review the generated deployment output before installing.

## Minimal test gate

Do not begin with the full Blockcraft world. First replace the game payload temporarily with a diagnostic LÖVE app that displays the runtime version, draws a rectangle, writes a test save through `love.filesystem`, and reports Xbox controller events. Deploy that package to Xbox One Developer Mode. Only after that passes should the normal Blockcraft payload be packaged.

No Xbox compatibility is claimed by creating this scaffold.

## Remote Windows builder

The repository includes `.github/workflows/build-xbox-uwp.yml`. From GitHub’s web interface, run **Actions → Build Blockcraft Xbox UWP → Run workflow** and provide HTTPS URLs for matching x64 UWP SDL2 and ANGLE bundles. The workflow uses a Windows runner to build the engine and host, then uploads logs and build artifacts. See `GITHUB_ACTIONS_BUILDER.md` for the required bundle layout and the iPhone steps.

The workflow is a build helper, not an Xbox compatibility test. It does not replace MSIX signing, Xbox Device Portal deployment, or the minimal diagnostic-app gate.

Before running it, use **Build Xbox UWP Dependencies** in the GitHub Actions tab. That no-input workflow builds the pinned SDL2 UWP and ANGLE UWP bundles and uploads them as an artifact. Publish those two ZIPs in a repository release, then use their direct asset URLs in the main workflow form.
