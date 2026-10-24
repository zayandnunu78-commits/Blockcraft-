# Rebuilding the mobile LÖVE runtime with HTTPS

The Blockcraft `.love` game archive cannot add native HTTPS support by itself. The mobile LÖVE runtime must include the `lua-https` native module, or the runtime must be LÖVE 12 with its built-in `https` module.

## First identify your mobile platform

The screenshot appears to be from an iOS-style runtime. If you installed Blockcraft inside an existing LÖVE player app, you cannot update the runtime by replacing the `.love` file. The app developer must rebuild the player, or you must build the player from its source.

## Android: LÖVE 11.4+

1. Install Android Studio, the Android SDK/NDK required by the selected `love-android` revision, Git, CMake, and OpenSSL/cURL development components required by `lua-https`.
2. Clone the `love-android` source matching the LÖVE version used by the game, preferably 11.5.
3. Download or clone `lua-https` from `https://github.com/love2d/lua-https`.
4. Place the module source at this exact location inside the LÖVE Android source:

   ```text
   love-android/love/src/jni/lua-modules/lua-https/
   ```

   The module directory should contain its source and build files, including `src`, `CMakeLists.txt`, and the Android build file supplied by `lua-https`.
5. Build the Android LÖVE app using the repository’s Gradle/Android build instructions. The native module must be compiled into the APK for every ABI you ship, especially `arm64-v8a`.
6. Install the rebuilt APK on the device.
7. Put the updated Blockcraft `.love` file into the rebuilt app using the runtime’s normal game-loading method.
8. Open the account screen and test registration. The previous “no HTTPS module” message should be gone.

The official LÖVE documentation describes this Android module location and explains that `lua-https` must be compiled into the APK; copying a desktop `https.so` into an Android game will not work.

## iOS: LÖVE iOS/Xcode runtime

1. Obtain the source for the LÖVE iOS player app you are using. A third-party player app cannot be modified through the Blockcraft archive alone.
2. Add the `lua-https` source to the Xcode project’s native module target.
3. Build the module for every iOS architecture supported by the app and link the required Apple networking/security frameworks used by the module.
4. Embed the resulting native module in the app target, then build and install the new signed app from Xcode.
5. Load the updated Blockcraft `.love` file into that rebuilt player and test account registration.

If you do not have the iOS player source or an Apple development setup, the practical option is to ask the player-app developer for a version with `lua-https` enabled. Installing a new `.love` file cannot add the missing native module.

## LÖVE 12 option

LÖVE 12 includes the `https` module, but the official version history lists 12.0 as in development. If you use a LÖVE 12 build, rebuild the mobile player against that runtime and verify that `require("https")` works on the target device.

## Blockcraft files after rebuilding

Use the Firebase-connected archive after the runtime is fixed:

```text
BLOCKCRAFT_1_FIREBASE_MOBILE_HTTPS_FIX.zip
```

Extract the project, or use the `.love` file produced by your normal Blockcraft packaging process. Keep `account/firebase_config.lua` with the Firebase Web API key and database URL. Never include Firebase service-account private keys in the game.
