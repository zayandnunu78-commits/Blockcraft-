/*
 * Windows Runtime (WinRT) support routines for PhysicsFS.
 *
 * Please see the file LICENSE.txt in the source's root directory.
 *
 *  This file originally written by Martin "T-Bone" Ahrnbom, but was mostly
 *  merged into physfs_platform_windows.c by Ryan C. Gordon (so please harass
 *  Ryan about bugs and not Martin).
 */

/* (There used to be instructions on how to make a WinRT project, but at
   this point, either CMake will do it for you or you should just drop
   PhysicsFS's sources into your existing project. --ryan.) */

#define __PHYSICSFS_INTERNAL__
#include "physfs_platforms.h"

#ifdef PHYSFS_PLATFORM_WINRT

#if defined(_MSC_VER) && !defined(_CRT_SECURE_NO_WARNINGS)
#define _CRT_SECURE_NO_WARNINGS 1
#endif
#include <windows.h>
#include <winrt/Windows.ApplicationModel.h>
#include <winrt/Windows.Storage.h>
#include <string>

#include "physfs_internal.h"

const void *__PHYSFS_winrtCalcBaseDir(void)
{
    static const std::wstring path =
        winrt::Windows::ApplicationModel::Package::Current().InstalledLocation().Path().c_str();
    return path.c_str();
} /* __PHYSFS_winrtCalcBaseDir */

const void *__PHYSFS_winrtCalcPrefDir(void)
{
    static const std::wstring path =
        winrt::Windows::Storage::ApplicationData::Current().LocalFolder().Path().c_str();
    return path.c_str();
} /* __PHYSFS_winrtCalcBaseDir */


#endif /* PHYSFS_PLATFORM_WINRT */

/* end of physfs_platform_winrt.cpp ... */

