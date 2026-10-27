# LightStudio.WebGPU

Dawn's native WebGPU C API for Linux, Android, Windows, macOS and iOS, usable
without ONNX Runtime. The package contains native libraries, matching public C/C++ headers,
standalone Dawn API dispatch sources, ABI-specific NativeBindings profiles, and
native dependency notices. It has no managed
binding or ONNX package dependency.

## Platforms

| RIDs | Requirements |
| --- | --- |
| `linux-x64`, `linux-arm64` | glibc 2.39 baseline; compatible Vulkan driver/loader |
| `android-arm64`, `android-x64` | Android 8.1 (API 27) or later; compatible Vulkan driver |
| `osx-arm64` | macOS 13 or later; Metal |
| `ios-arm64`, `iossimulator-arm64` | iOS 16 or later; Metal; static ARM64 device/simulator archives |
| `win-x64`, `win-arm64` | Windows 10 or later; compatible D3D12 driver; system `d3dcompiler_47.dll` |

NuGet selects the native library under `runtimes/<rid>/native/`: `libwebgpu_dawn.so`
on Linux/Android, `libwebgpu_dawn.dylib` on macOS, `webgpu_dawn.dll` on Windows,
and `libwebgpu_dawn.a` on iOS. Windows also includes the matching import `.lib`.
The library implements the WebGPU C entry points directly; no ONNX session,
execution-provider registration, or Dawn proc-table setup is required. The C++
runtime is linked statically on Linux, Android and Windows. Apple uses the system
C++ runtime. Android uses 16 KB page alignment and does not
require `libc++_shared.so`. GPU availability depends on the platform driver.
The iOS build targets automatically link the static archive, C++ runtime, and
Metal, Foundation, IOSurface and QuartzCore frameworks. Use `__Internal` for iOS
P/Invoke imports. Windows uses the system D3D12/FXC path without requiring the
Agility SDK or bundling DXC; optional features requiring DXC are unavailable.
Apple x64, browser WASM, musl, and non-iOS static libraries are not included.

## NativeBindings

Use the NativeBindings toolkit separately to generate managed declarations:

```xml
<ItemGroup>
  <PackageReference Include="LightStudio.WebGPU" Version="156.0.0" />
</ItemGroup>
<PropertyGroup>
  <AllowUnsafeBlocks>true</AllowUnsafeBlocks>
  <NativeBindingsEnabled>true</NativeBindingsEnabled>
  <NativeBindingsPackageDirectory>$(LightStudioWebGPUPackageRoot)</NativeBindingsPackageDirectory>
  <NativeBindingsProfile>$(RuntimeIdentifier)</NativeBindingsProfile>
  <NativeBindingsStatic>false</NativeBindingsStatic>
</PropertyGroup>
```

In a project with the toolkit imported:

```csharp
using System.Reflection;
using LightStudio.NativeBindings;

[Include("webgpu/webgpu.h", Access = BindingFlags.Public)]
public static unsafe partial class WebGPU;
```

Select an explicit supported runtime, for example `dotnet build -r linux-x64`.
For `ios-arm64` and `iossimulator-arm64`, set `NativeBindingsStatic` to `true`
instead of `false`; those profiles use `__Internal` rather than a shared library.
Configure the provider in the project generating these declarations; the package
does not change the provider for unrelated native bindings in the application.
The toolkit supplies generated declarations, not WebGPU ownership wrappers.

The package follows the same schema-v1 native profile contract as
`LightStudio.Ffmpeg`:

```text
buildTransitive/LightStudio.WebGPU.props
buildTransitive/LightStudio.WebGPU.targets
native-bindings/manifest.json
native-bindings/profiles/<rid>/profile.json
native-bindings/profiles/<rid>/include/webgpu/webgpu.h
native-bindings/profiles/<rid>/include/dawn/webgpu.h
native-bindings/profiles/<rid>/include/dawn/dawn_proc_table.h
native-bindings/profiles/<rid>/configuration/build.json
dawn-api/<rid>/include/dawn/
dawn-api/<rid>/include/webgpu/
dawn-api/<rid>/src/dawn_proc.cpp
dawn-api/<rid>/src/dawn_thread_dispatch_proc.cpp
dawn-api/<rid>/LICENSE
runtimes/<rid>/native/<platform-native-library>
```

`LightStudioWebGPUPackageRoot` exposes the restored package directory, and
`LightStudioWebGPUNativeBindingsManifest` exposes its manifest. Every profile
contains the exact generated Dawn header and public forwarding header from its
native build, compiler-derived target triple, widths and signedness, toolchain
and SDK identity, the native library's format, runtime identity and dependencies, and content
hashes. Packing rejects missing profiles, mismatched Dawn source revisions,
and changed headers or binaries.
The Dawn API export is also hash-validated and uses the same generated version
header as the native library. Its dispatch sources need only the exported
headers and the C++20 standard library; the proc-table version check is retained.
Symbol extraction and frontend ABI conformance remain toolkit responsibilities,
as with the FFmpeg profile format; the manifest is marked `prototype`.

## Building And Releases

Dawn builds independently of ONNX. The repository-owned `Dawn.props` pins
Chromium release `156.0.8078.47`'s Dawn commit
`1da41e55bb915dd03f61028fad64a99ee1786d48`.
Sources are checked out from the official Dawn Git repository at
`dawn.googlesource.com`, using the immutable commit rather than a moving
Chromium branch. Git is required on build hosts, not on consumer machines.
The NuGet version defaults to `156.0.0` and follows
`<Chromium milestone>.<Dawn snapshot increment>.<packaging fix>` independently
of ONNX. The milestone does not guarantee Dawn C API or ABI compatibility;
always use the matching headers and native library. Each build writes
`artifacts/webgpu-<rid>`:

```sh
bash scripts/build-webgpu.sh linux-x64
dotnet pack package/webgpu/LightStudio.WebGPU.csproj -c Release \
  -o artifacts/packages -p:WebGPURuntimeIdentifiers=linux-x64 \
  -p:PackageVersion=156.0.0-local.1
```

Milestone-based versions sort below the previous date-based versions in NuGet.
Existing consumers must explicitly select `156.0.0` when migrating; automatic
update discovery will not treat it as newer than a date-based release.

Use `scripts/webgpu-linux.Dockerfile` for release-compatible glibc requirements.
Android uses NDK r28c and `ANDROID_API` defaults to 27. `WEBGPU_BUILD_DIR` overrides
the isolated build directory, and `JOBS` controls parallelism.
Apple builds require Xcode, CMake, Ninja, Jinja2 and packaging. Run
`bash scripts/build-webgpu.sh osx-arm64`, `ios-arm64`, or `iossimulator-arm64` on
a Mac. `MACOSX_DEPLOYMENT_TARGET` defaults to 13.0 and
`IPHONEOS_DEPLOYMENT_TARGET` defaults to 16.0. iOS and simulator archives are
distinct; they cannot be interchanged despite both using ARM64.

Windows builds require Visual Studio C++ tools (including ARM64 cross tools),
the Windows SDK, LLVM's `clang-cl`/`lld-link`/`llvm-readobj`, CMake, Ninja, Python,
Jinja2, packaging, and Git Bash on `PATH`. Initialize `vcvarsall.bat x64` for
`win-x64` or `vcvarsall.bat x64_arm64` for `win-arm64`, then invoke
`bash scripts/build-webgpu.sh <rid>` from that developer environment.

Complete releases require all nine WebGPU native outputs. `WebGPUArtifactsPath`
overrides the staging root and `WebGPUProfilePython` selects the build-only
Python 3.9+ interpreter. Consumers do not need Python.

The dedicated `.github/workflows/webgpu.yml` builds all nine RIDs and publishes
only WebGPU on `webgpu-v<package-version>` tags. Manual dispatch defaults to the
pinned Dawn package version; `package_version` overrides it, and `publish=true`
creates the corresponding GitHub release. The default `publish=false` uploads
only workflow artifacts. `-p:PackageVersion=...` provides the local pack override;
neither override changes the pinned Dawn sources.

ONNX downloads this `.nupkg` from the `webgpu-v<package-version>` GitHub release
and uses `dawn-api/<rid>` with `onnxruntime_DAWN_PREBUILT_DIR`; it does not fetch
or build Dawn. See ONNX Runtime's
[external Dawn contract](https://github.com/microsoft/onnxruntime/blob/main/docs/WebGPU_External_Dawn.md).
ONNX WebGPU consumers must supply the matching `dawnProcTable` provider option;
standalone WebGPU C API consumers need no ONNX or proc-table setup.
Dawn's BSD license, third-party notices, and static C++ runtime notices are
included under `licenses/<rid>/`.