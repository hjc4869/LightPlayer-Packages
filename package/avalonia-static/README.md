# LightStudio.AvaloniaStatic

Static native dependencies for Avalonia 12 NativeAOT. The default package
version is **12.1.3**.

## Contents

| Component | Source |
| --- | --- |
| Skia / libSkiaSharp | SkiaSharp **4.153.1**, including its bundled codec dependencies |
| HarfBuzz / libHarfBuzzSharp | **14.2.1 / 14.2.1.301**, from the same SkiaSharp release |
| ANGLE | **chromium/7922**, complete `libANGLE_static` and `libGLESv2_static` archives |
| Avalonia.Native (macOS only) | [hjc4869/Avalonia release/12.1.3](https://github.com/hjc4869/Avalonia/tree/release/12.1.3) |

The Skia set also includes the separately emitted Skottie, resource provider,
scene graph, shaper, and JSON reader archives required by the 4.153.1 native API.
On macOS, ANGLE is shipped for explicit use but not linked automatically;
Avalonia.Native uses the system Metal/OpenGL backends.

Sources are commit-pinned in `scripts/avalonia-static/sources.json`. Each RID has
source revisions and build arguments in `build-info/` and upstream notices in
`licenses/`. No managed Avalonia assemblies are rebuilt by this pipeline.

| RIDs | Native build baseline |
| --- | --- |
| `linux-x64`, `linux-arm64` | Ubuntu 24.04 / glibc 2.39 build environment |
| `win-x64`, `win-arm64` | Windows 10+, Visual Studio 2022, static MSVC CRT |
| `osx-x64`, `osx-arm64` | macOS 11+, Metal and OpenGL, matching Avalonia.Native archive |
| `android-x64`, `android-arm64` | API 27, NDK r28c, PIC archives; final links request 16 KB pages |

Static archives live under `static/<rid>/`, not `runtimes/`. The package does not
make the OS or C/C++ runtime fully static. Linux still needs system fontconfig,
GL/X11 and libc; macOS uses system frameworks; Android uses platform EGL/GLES
and the consuming NDK's static C++ runtime. Skia Vulkan is disabled.

## Consume

```xml
<PropertyGroup>
  <PublishAot>true</PublishAot>
</PropertyGroup>
<ItemGroup>
  <PackageReference Include="LightStudio.AvaloniaStatic" Version="12.1.3" />
</ItemGroup>
```

```sh
dotnet publish -c Release -r linux-x64
```

The package requires Avalonia **12.1.3**, SkiaSharp **4.153.1**, and HarfBuzzSharp
**14.2.1.301** managed bindings. Exact NuGet dependencies prevent accidentally
pairing another native ABI with these archives. Use matching versions of your
other Avalonia packages, including Avalonia.Desktop or Avalonia.Android.

`buildTransitive` targets select archives, direct P/Invokes, OS libraries, and
macOS frameworks for `PublishAot=true`. They filter replaced SkiaSharp,
HarfBuzzSharp, Windows ANGLE, and macOS Avalonia.Native dynamic assets from
publish output. Set `EnableStaticAvalonia=false` to disable integration. Normal
non-NativeAOT builds are unchanged. Do not combine with StaticLink.Avalonia or
another package providing these same static archives.

Android archives are suitable for a NativeAOT/native host toolchain that honors
`NativeLibrary`, `DirectPInvoke`, and `NativeSystemLibrary`. Standard .NET Android
Mono AOT (`RunAOTCompilation`) is not NativeAOT and does not link these archives
automatically. A custom host must link them with the NDK and expose the expected
P/Invoke symbols; this package does not provide such a host or replace the
Android runtime. Desktop NativeAOT also requires the platform's native SDK.

## Build And Release

Run **Build and publish LightStudio.AvaloniaStatic** in GitHub Actions. Set
`package_version` (default `12.1.3`) and leave `publish=false` for an artifact-only
build. All eight jobs must succeed before packing. Set `publish=true` to publish
using the repository's `NUGET_API_KEY` secret. A tag `avalonia-static-v12.1.3`
also builds and uploads the package without publishing to NuGet.org.

Changing the package version changes only the NuGet version, not source pins.
Updating Avalonia.Native requires updating its fork revision and the matching
managed dependency together. There are no legacy Avalonia source branches.

Compilation uses the host CPU count by default; set `JOBS` to override it.
Skia and ANGLE dependency checkouts are serialized, with up to three sync
attempts. CI caches the native work directory separately for each RID and build
configuration, and checks the macOS Metal compiler before building.

The depot-tools checkout keeps the directory name `depot_tools` so its Ninja
wrapper can find the installed Ninja without calling itself. Windows explicitly
bootstraps depot-tools, including its Git wrapper, before dependency sync.

Local build, with the same host tools as the workflow:

```sh
python3 scripts/build-avalonia-static.py linux-x64
dotnet pack package/avalonia-static/LightStudio.AvaloniaStatic.csproj -c Release -o artifacts/packages
```

Collect `artifacts/avalonia-static-<rid>` from every platform before packing;
missing archives, provenance, or required notices cause packing to fail.
Workflows follow this repository's build/pack/upload convention and do not run
application smoke tests. Run a real application publish and rendering smoke
test on each target before distributing a release to consumers.
