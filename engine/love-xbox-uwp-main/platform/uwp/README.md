# UWP

This branch builds LÖVE 11.5 as a UWP DLL and static entry-point library. It uses an external UWP SDL installation and can use SDL's ANGLE/EGL path. The application project remains responsible for its manifest, assets, ANGLE DLLs, and runtime dependency DLLs.

UWP builds expose `love.system.httpDownload(url, path, userAgent, accept)` for app owned downloads through Windows HTTP.

LuaJIT is enabled by default and pinned to an upstream revision with UWP support. Its host tools require the x64 MSVC desktop libraries, so the bundled LuaJIT target currently supports x64 only.

Configure from a Visual Studio developer shell:

```powershell
cmake -S . -B build/uwp-x64-angle `
    -G "Visual Studio 17 2022" -A x64 `
    -DCMAKE_SYSTEM_NAME=WindowsStore `
    -DCMAKE_SYSTEM_VERSION=10.0 `
    -DCMAKE_TOOLCHAIN_FILE=C:/path/to/vcpkg/scripts/buildsystems/vcpkg.cmake `
    -DVCPKG_TARGET_TRIPLET=x64-uwp `
    -DLOVE_UWP_SDL_ROOT=C:/path/to/sdl2-install `
    -DLOVE_UWP_ANGLE=ON

cmake --build build/uwp-x64-angle --config RelWithDebInfo
```

`LOVE_UWP_SDL_ROOT` must contain `include/SDL2` and `lib/SDL2.lib`. The build produces `liblove.dll`, its import library, `lovestatic.lib`, and `lua51.dll`.
