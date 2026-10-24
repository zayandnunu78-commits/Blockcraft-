# Remote Windows builder with GitHub Actions

GitHub Actions can run this project on a GitHub-hosted Windows virtual machine. The workflow is in `.github/workflows/build-xbox-uwp.yml`. It is manual-only and does not run automatically on every push.

## Build the dependency bundles first

The repository also includes `.github/workflows/build-xbox-uwp-dependencies.yml`. This workflow has no URL fields. Run **Actions → Build Xbox UWP Dependencies → Run workflow**. It builds the pinned Xbox-compatible SDL2 UWP revision and ANGLE UWP for x64/D3D11, then uploads `sdl2-x64-uwp.zip` and `angle-x64-uwp.zip` as one artifact. ANGLE is a large build and may take a long time.

Download that artifact from the completed workflow run. Create a repository release such as `uwp-deps-v1`, upload both ZIPs, and publish it. The release asset URLs can then be pasted into the two fields in **Build Blockcraft Xbox UWP**. Do not paste the Actions artifact page URL; the main workflow needs direct HTTPS ZIP URLs from the release assets.

## What the workflow does

The workflow runs on `windows-2022`, prepares MSBuild/MSVC, downloads the SDL2 UWP and ANGLE UWP bundles supplied at dispatch time, bootstraps vcpkg, builds the LÖVE UWP engine, configures the Blockcraft host, builds the host, and uploads the build directories and inventory as an artifact. It intentionally does not sign or claim that the package is ready for Xbox.

The workflow requires two URLs when you click **Run workflow**:

- An SDL2 x64 UWP ZIP whose root contains `include/SDL2/SDL.h`, `lib/SDL2.lib`, and `bin/SDL2.dll`.
- An ANGLE x64 UWP ZIP whose root contains `bin/libEGL.dll`, `bin/libGLESv2.dll`, and `bin/d3dcompiler_47.dll`.

Those bundles must be built for Windows UWP and must match the engine’s x64 configuration. Do not use ordinary desktop SDL2 or desktop ANGLE binaries. The workflow downloads the URLs on the runner, so use HTTPS URLs that do not require an interactive login.

## How to run it from an iPhone

1. Create or open a GitHub repository containing this project.
2. Upload the project ZIP contents, including `.github/workflows/build-xbox-uwp.yml`.
3. Open the repository in Safari and select **Actions**.
4. Select **Build Blockcraft Xbox UWP**.
5. Choose **Run workflow**, enter the two dependency bundle URLs, and start the run.
6. Open the run after it finishes and download `blockcraft-xbox-uwp-windows-build-*`.

If the workflow does not appear, the workflow file has not reached the repository’s default branch or Actions are disabled for the repository.

## What is still required after a successful CI build

The current host scaffold does not yet stage every SDL2, ANGLE, and vcpkg runtime DLL into a finished MSIX. A successful workflow run therefore proves only that the selected native sources configured and compiled in the remote Windows environment. It does not prove Xbox compatibility.

The next packaging pass must stage all runtime DLLs, generate/sign the MSIX with a development certificate, install it through Xbox Device Portal, and run the minimal diagnostic LÖVE app before packaging the full Blockcraft game. Keep the PFX private in GitHub Actions secrets; never commit it to the repository.

The workflow is deliberately configured to upload logs even when a build step fails. The first failing step and its complete CMake/MSBuild output should be fixed before attempting Blockcraft runtime testing.
