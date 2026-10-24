# BLOCKCRAFT 1 — Camera/Render Stability Build

This is a separate copy of the supplied BLOCKCRAFT 1 project. The supplied archive and the earlier working copy were left unchanged.

## Changes in this build

- The frame draw callback explicitly clears the background color and depth buffer before drawing the 3D scene. This avoids relying on driver-specific implicit depth-buffer clearing, which can leave stale depth values during camera motion and produce missing/flickering geometry.
- Camera projection resize now rejects zero, negative, non-numeric, or infinite viewport dimensions and keeps the last valid projection. The resize callback no longer recalculates the projection twice.
- World generation, block textures, player controls, menus, saves, multiplayer protocol, and server port are otherwise unchanged.

## Launch

Install LÖVE 11.5 or a compatible LÖVE 11.x build, then launch the client from this project folder:

```sh
love .
```

This is the supplied online-only BLOCKCRAFT 1 build: multiplayer still expects a compatible server on UDP **22122**. This package does not deploy, restart, or modify any live server.

## Tests performed

From the project root:

```sh
lua tests/camera_stability_test.lua
lua tests/cloud_save_test.lua
lua tests/menu_navigation_test.lua
```

The original cloud-save and menu-navigation test scripts are retained. The camera test verifies valid viewport resizing and rejects invalid dimensions without producing a non-finite projection. All Lua files should also parse under Lua 5.1/LuaJIT.

A local LÖVE render smoke test exercised a rotating camera and window resizing. It showed no graphics/shader errors in the sandbox. This is not a test on the user's device or the live multiplayer server; if the screen still flickers or distorts there, a screenshot/short recording and device/OS details will be needed to identify the remaining cause.
