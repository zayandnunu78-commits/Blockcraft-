cmake_minimum_required(VERSION 3.24)
project(BlockcraftUWP LANGUAGES CXX)

if(NOT CMAKE_SYSTEM_NAME STREQUAL "WindowsStore")
    message(FATAL_ERROR "Configure this project with the WindowsStore/UWP toolchain.")
endif()

set(BLOCKCRAFT_ENGINE_ROOT "${CMAKE_CURRENT_LIST_DIR}/../engine/love-xbox-uwp-main" CACHE PATH
    "Path to the LÖVE Xbox UWP source tree")
set(BLOCKCRAFT_SDL_ROOT "" CACHE PATH
    "Path to the SDL2 x64 UWP installation")
set(BLOCKCRAFT_LOVE_BUILD "${BLOCKCRAFT_ENGINE_ROOT}/build/uwp-x64-angle/RelWithDebInfo" CACHE PATH
    "Directory containing the built LÖVE UWP libraries")
set(BLOCKCRAFT_LOVE_RUNTIME "${BLOCKCRAFT_LOVE_BUILD}/liblove.dll" CACHE FILEPATH
    "Built LÖVE shared runtime")
set(BLOCKCRAFT_LUA_RUNTIME "${BLOCKCRAFT_LOVE_BUILD}/lua51.dll" CACHE FILEPATH
    "Built LuaJIT runtime")
set(BLOCKCRAFT_LOVESTATIC "${BLOCKCRAFT_LOVE_BUILD}/lovestatic.lib" CACHE FILEPATH
    "Built LÖVE static entry-point library")
set(BLOCKCRAFT_LIBLOVE "${BLOCKCRAFT_LOVE_BUILD}/liblove.lib" CACHE FILEPATH
    "Built LÖVE import library")
set(BLOCKCRAFT_LUA_LIB "${BLOCKCRAFT_LOVE_BUILD}/lua51.lib" CACHE FILEPATH
    "Built LuaJIT import library")
set(BLOCKCRAFT_GAME_ROOT "${CMAKE_CURRENT_LIST_DIR}/../BLOCKCRAFT_1_xbox_controller" CACHE PATH
    "Blockcraft game source directory")

if(NOT EXISTS "${BLOCKCRAFT_LIBLOVE}")
    file(GLOB_RECURSE BLOCKCRAFT_LIBLOVE_CANDIDATES
        "${BLOCKCRAFT_LOVE_BUILD}/*love*.lib")
    foreach(candidate IN LISTS BLOCKCRAFT_LIBLOVE_CANDIDATES)
        if(NOT candidate MATCHES "lovestatic\\.lib$")
            set(BLOCKCRAFT_LIBLOVE "${candidate}" CACHE FILEPATH
                "Built LÖVE import library" FORCE)
            break()
        endif()
    endforeach()
endif()

foreach(required_path IN ITEMS BLOCKCRAFT_SDL_ROOT BLOCKCRAFT_GAME_ROOT)
    if(NOT EXISTS "${${required_path}}")
        message(FATAL_ERROR "Missing required path ${required_path}: ${${required_path}}")
    endif()
endforeach()

foreach(required_file IN ITEMS BLOCKCRAFT_LOVE_RUNTIME BLOCKCRAFT_LUA_RUNTIME BLOCKCRAFT_LOVESTATIC BLOCKCRAFT_LIBLOVE BLOCKCRAFT_LUA_LIB)
    if(NOT EXISTS "${${required_file}}")
        message(FATAL_ERROR "Missing built LÖVE artifact ${required_file}: ${${required_file}}")
    endif()
endforeach()

set(GAME_ARCHIVE "${CMAKE_CURRENT_BINARY_DIR}/blockcraft.love")
file(GLOB_RECURSE BLOCKCRAFT_GAME_FILES CONFIGURE_DEPENDS
    "${BLOCKCRAFT_GAME_ROOT}/*")
add_custom_command(
    OUTPUT "${GAME_ARCHIVE}"
    COMMAND "${CMAKE_COMMAND}" -E rm -f "${GAME_ARCHIVE}"
    COMMAND "${CMAKE_COMMAND}" -E tar cf "${GAME_ARCHIVE}" --format=zip .
    WORKING_DIRECTORY "${BLOCKCRAFT_GAME_ROOT}"
    DEPENDS ${BLOCKCRAFT_GAME_FILES}
    VERBATIM
)
add_custom_target(blockcraft_payload ALL DEPENDS "${GAME_ARCHIVE}")

set(PACKAGE_MANIFEST "${CMAKE_CURRENT_BINARY_DIR}/Package.appxmanifest")
set(BLOCKCRAFT_PACKAGE_VERSION "0.1.0.0" CACHE STRING "MSIX package version")
set(BLOCKCRAFT_PUBLISHER "CN=Blockcraft Development" CACHE STRING "Signing certificate subject")
configure_file(
    "${CMAKE_CURRENT_LIST_DIR}/Package.appxmanifest.in"
    "${PACKAGE_MANIFEST}"
    @ONLY
)

add_executable(BlockcraftUWP WIN32 app/main.cpp)
add_dependencies(BlockcraftUWP blockcraft_payload)
set_target_properties(BlockcraftUWP PROPERTIES
    CXX_STANDARD 17
    CXX_STANDARD_REQUIRED YES
    VS_GLOBAL_DefaultLanguage "en-US"
    VS_SDK_REFERENCES "Microsoft.VCLibs, Version=14.0"
)
target_include_directories(BlockcraftUWP PRIVATE "${BLOCKCRAFT_SDL_ROOT}/include/SDL2")
target_link_libraries(BlockcraftUWP PRIVATE
    "${BLOCKCRAFT_LOVESTATIC}"
    "${BLOCKCRAFT_LIBLOVE}"
    "${BLOCKCRAFT_SDL_ROOT}/lib/SDL2.lib"
    "${BLOCKCRAFT_LUA_LIB}"
    WindowsApp.lib
)

set(PACKAGE_CONTENT
    "${PACKAGE_MANIFEST}"
    "${GAME_ARCHIVE}"
    "${BLOCKCRAFT_LOVE_RUNTIME}"
    "${BLOCKCRAFT_LUA_RUNTIME}"
)
foreach(content IN LISTS PACKAGE_CONTENT)
    set_source_files_properties("${content}" PROPERTIES
        VS_COPY_TO_OUT_DIR Always
        VS_DEPLOYMENT_CONTENT TRUE
        VS_DEPLOYMENT_LOCATION "."
    )
endforeach()

file(GLOB PACKAGE_ASSETS CONFIGURE_DEPENDS "${CMAKE_CURRENT_LIST_DIR}/Assets/*.png")
set_source_files_properties(${PACKAGE_ASSETS} PROPERTIES
    VS_DEPLOYMENT_CONTENT TRUE
    VS_DEPLOYMENT_LOCATION "Assets"
)
target_sources(BlockcraftUWP PRIVATE ${PACKAGE_CONTENT} ${PACKAGE_ASSETS})
