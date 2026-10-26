# LightStudio.WebGPU

Dawn's native WebGPU C API for Linux and Android, usable without ONNX Runtime.
The package contains `libwebgpu_dawn.so`, matching public C/C++ headers,
standalone Dawn API dispatch sources, ABI-specific NativeBindings profiles, and
native dependency notices. It has no managed
binding or ONNX package dependency.

## Platforms

| RIDs | Requirements |
| --- | --- |
| `linux-x64`, `linux-arm64` | glibc 2.39 baseline; compatible Vulkan driver/loader |
| `android-arm64`, `android-x64` | Android 8.1 (API 27) or later; compatible Vulkan driver |

NuGet selects `runtimes/<rid>/native/libwebgpu_dawn.so` for the consumer RID.
The library implements the WebGPU C entry points directly; no ONNX session,
execution-provider registration, or Dawn proc-table setup is required. The C++
runtime is linked statically. Android uses 16 KB page alignment and does not
require `libc++_shared.so`. GPU availability depends on the platform driver.
Apple, Windows, browser WASM, musl, and static libraries are not included.

## NativeBindings

Use the NativeBindings toolkit separately to generate managed declarations:

```xml
<ItemGroup>
  <PackageReference Include="LightStudio.WebGPU" Version="20260818.211311.0" />
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
Configure the provider in the project generating these declarations; the package
does not change the provider for unrelated native bindings in the application.
The toolkit supplies generated declarations, not WebGPU ownership wrappers.

The package follows the same schema-v1 native profile contract as
`LightStudio.Ffmpeg`:

```text
buildTransitive/LightStudio.WebGPU.props
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
runtimes/<rid>/native/libwebgpu_dawn.so
```

`LightStudioWebGPUPackageRoot` exposes the restored package directory, and
`LightStudioWebGPUNativeBindingsManifest` exposes its manifest. Every profile
contains the exact generated Dawn header and public forwarding header from its
native build, compiler-derived target triple, widths and signedness, toolchain
and SDK identity, the shared library's SONAME and dependencies, and content
hashes. Packing rejects missing profiles and changed headers or binaries.
The Dawn API export is also hash-validated and uses the same generated version
header as the native library. Its dispatch sources need only the exported
headers and the C++20 standard library; the proc-table version check is retained.
Symbol extraction and frontend ABI conformance remain toolkit responsibilities,
as with the FFmpeg profile format; the manifest is marked `prototype`.

## Building And Releases

Dawn builds independently of ONNX. The repository-owned `Dawn.props` pins
upstream tag `v20260818.211311`, commit
`f5df92664181659d3e5c29e01e8f0342ae4565d4`, and the source archive checksum.
The NuGet version defaults to `20260818.211311.0`, the NuGet-normalized form of
Dawn's upstream version, not the ONNX version. Each build writes
`artifacts/webgpu-<rid>`:

```sh
bash scripts/build-webgpu.sh linux-x64
dotnet pack package/webgpu/LightStudio.WebGPU.csproj -c Release \
  -o artifacts/packages -p:WebGPURuntimeIdentifiers=linux-x64 \
  -p:PackageVersion=20260818.211311.0-local.1
```

Use `scripts/webgpu-linux.Dockerfile` for release-compatible glibc requirements.
Android uses NDK r28c and `ANDROID_API` defaults to 27. `WEBGPU_BUILD_DIR` overrides
the isolated build directory, and `JOBS` controls parallelism.
Complete releases require all four WebGPU native outputs. `WebGPUArtifactsPath`
overrides the staging root and `WebGPUProfilePython` selects the build-only
Python 3.9+ interpreter. Consumers do not need Python.

The dedicated `.github/workflows/webgpu.yml` builds all four RIDs and publishes
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