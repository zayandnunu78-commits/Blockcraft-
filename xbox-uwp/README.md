# Blockcraft 1 Xbox UWP host scaffold

This directory is the application layer around the bundled `love-xbox-uwp-main` engine. It is intentionally separate from the Blockcraft game source and from the production multiplayer server.

## Current status

This is an Xbox UWP host scaffold with a Windows GitHub Actions build and signing workflow. It has not yet passed an end-to-end launch test on Xbox One Developer Mode; a successful Windows build or signature check alone does not establish Xbox compatibility.

The scaffold contains:

- `app/main.cpp`: WinRT host that launches the fused `blockcraft.love` payload through `SDL_WinRTRunApp` and `SDL_main`.
- `Package.appxmanifest.in`: package identity, visual assets, and network/code-generation capabilities.
- `CMakeLists.txt`: x64 WindowsStore host build, fused payload creation, dependency checks, and Visual Studio deployment content.
- `CMakePresets.json`: Visual Studio 17 2022 x64 UWP presets.
- `Assets/`: Xbox app tile, store, and splash-screen logo variants. The original source is preserved at `Assets/source/BlockcraftLogoSource.png`; the game menu uses `BLOCKCRAFT_1_xbox_controller/assets/blockcraft_logo.png`.

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
- `bin/SDL2.dll`, staged into the package by the Windows packaging project.

The ANGLE x64 UWP bundle must also contain `bin/libEGL.dll`, `bin/libGLESv2.dll`, and
`bin/d3dcompiler_47.dll`. CMake fails if any runtime file is missing, stages all four
SDL2/ANGLE DLLs into the MSIX root, and the GitHub Actions build verifies that the
finished package contains them before signing. The LÖVE engine also dynamically imports
`OpenAL32.dll`, `freetype.dll`, `ogg.dll`, `theora.dll`, `vorbisfile.dll`, and `z.dll`.
Those six x64 UWP runtime DLLs must be present in the vcpkg `installed/x64-uwp/bin`
directory. CMake stages them into the MSIX and fails early if any are absent.

## Configure and build

From a Visual Studio Developer PowerShell, first build the engine from its source directory using `platform/uwp/README.md`. Then configure the host:

```powershell
cd xbox-uwp
cmake --preset uwp-relwithdebinfo `
  -DBLOCKCRAFT_SDL_ROOT=C:/path/to/sdl2-install `
  -DBLOCKCRAFT_ANGLE_ROOT=C:/path/to/angle-uwp `
  -DBLOCKCRAFT_VCPKG_RUNTIME_DIR=C:/path/to/vcpkg/installed/x64-uwp/bin `
  -DBLOCKCRAFT_LOVE_BUILD=C:/path/to/love/build/RelWithDebInfo
cmake --build --preset uwp-relwithdebinfo
```

The generated Visual Studio package must contain SDL2, ANGLE, all six LÖVE vcpkg runtime DLLs, and its declared Microsoft.VCLibs framework dependency. The GitHub workflow checks these files and includes the VCLibs `.appx` in the signed install bundle. Install/trust the included development certificate and install the x64 VCLibs framework package before deploying the Blockcraft MSIX to Xbox Device Portal.

## Minimal test gate

Do not begin with the full Blockcraft world. First replace the game payload temporarily with a diagnostic LÖVE app that displays the runtime version, draws a rectangle, writes a test save through `love.filesystem`, and reports Xbox controller events. Deploy that package to Xbox One Developer Mode. Only after that passes should the normal Blockcraft payload be packaged.

No Xbox compatibility is claimed by creating this scaffold.

## Remote Windows builder

The repository includes `.github/workflows/build-xbox-uwp.yml`. From GitHub’s web interface, run **Actions → Build Blockcraft Xbox UWP → Run workflow** and provide HTTPS URLs for matching x64 UWP SDL2 and ANGLE bundles. The workflow uses a Windows runner to build the engine and host, then uploads logs and build artifacts. See `GITHUB_ACTIONS_BUILDER.md` for the required bundle layout and the iPhone steps.

The workflow is a build helper, not an Xbox compatibility test. It does not replace MSIX signing, Xbox Device Portal deployment, or the minimal diagnostic-app gate.

Before running it, use **Build Xbox UWP Dependencies** in the GitHub Actions tab. That no-input workflow builds the pinned SDL2 UWP and ANGLE UWP bundles and uploads them as an artifact. Publish those two ZIPs in a repository release, then use their direct asset URLs in the main workflow form.
