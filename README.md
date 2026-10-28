# LightPlayer Packages

This repository builds native, managed, and data-only NuGet packages for .NET:

- [LightStudio.Ffmpeg](package/ffmpeg/README.md): FFmpeg 9.0.2 with decoding and desktop transcoding dependencies.
- [LightStudio.Photos](package/photos/README.md): LibRaw 0.22.2, Little CMS 2.19.1 and jxrlib 1.1 for RAW photos, ICC color management and JPEG XR, with exact-build headers and NativeBindings profiles. See [Photos builds](#photos-builds) for its platform matrix and workflow.
- [LightStudio.Onnx](package/onnx/README.md): ONNX Runtime 1.30.0 with its complete .NET managed API for eight native RIDs, WebGPU through a LightStudio.WebGPU dependency on Linux and Android, and CoreML on macOS and iOS. See the package README for release build instructions and platform limitations.
- [LightStudio.WebGPU](package/webgpu/README.md): Independently built Dawn WebGPU C API for Linux/Android (Vulkan), Windows x64/ARM64 (D3D12), and macOS/iOS ARM64 (Metal), with upstream Dawn versioning, exact-build headers, standalone dispatch sources, and NativeBindings profiles.
- [LightStudio.sqlite-vec](package/sqlite-vec/README.md): sqlite-vec 0.1.9 shared and static native extensions for eight desktop/Android RIDs, static iOS ARM64 device/simulator extensions, and single-threaded/multithreaded browser-WASM static libraries, with bundled SQLite for Android/WASM. Windows can use the system WinSQLite engine.
- [LightStudio.AvaloniaStatic](package/avalonia-static/README.md): Static SkiaSharp 4.153.1, HarfBuzzSharp 14.2.1.301, and ANGLE for Windows, Linux, macOS, and Android on x64 and ARM64, with no managed Avalonia dependency.
- [LightStudio.GeoNames](package/geonames/README.md): Data-only offline cities1000 database with country and administrative names, seven name languages, stable GeoNames IDs, and a balanced spherical search index. Its independent workflow builds from GeoNames snapshots and packages the gzip-compressed binary with provenance, attribution, and MSBuild paths for embedding.
- [LightStudio.Fonts](package/fonts/README.md): Data-only Noto Sans CJK SC Regular and Bold OpenType fonts, with the SIL Open Font License and an MSBuild asset directory. Its independent workflow packs the fonts and publishes GitHub releases.

The workflows build, stage, pack, and upload artifacts without post-build tests or validation. Pre-build lint and toolchain/configuration checks remain enabled.

Successful tag builds publish GitHub releases with the generated `.nupkg` files attached. Manual dispatch publishes a release only with `publish=true`; the default `publish=false` keeps the build artifact-only. Releases use the built-in `GITHUB_TOKEN`, with no NuGet.org push or API key required.

## FFmpeg Runtimes

| Runtime | Linking | Location in the package |
| --- | --- | --- |
| `android-arm64`, `android-x64` | Shared (`.so`) | `runtimes/android-<arch>/native` |
| `android-arm64`, `android-x64` | Static (`.a`, native AOT opt-in) | `static/android-<arch>` |
| `win-x64`, `win-arm64` | Shared (`.dll`) | `runtimes/win-<arch>/native` |
| `win-x64`, `win-arm64` | Static (`.lib`, NativeAOT only) | `static/win-<arch>` |
| `osx-arm64` | Shared (`.dylib`) | `runtimes/osx-arm64/native` |
| `osx-arm64` | Static (`.a`, native AOT only) | `static/osx-arm64` |
| `ios-arm64` | Static (`.a`, device only) | `runtimes/ios-arm64/native` |
| `iossimulator-arm64` | Static (`.a`, ARM64 simulator) | `runtimes/iossimulator-arm64/native` |
| `browser-wasm`, single-threaded | Static (`.a`) | `static/wasm-em3`, `static/wasm-em6` |
| `browser-wasm`, multi-threaded | Static (`.a`) | `static/wasm-mt-em3`, `static/wasm-mt-em6` |

Desktop and browser static archives are kept outside `runtimes/` and linked by the package's `build/LightStudio.Ffmpeg.targets`. iOS archives use `runtimes/ios-arm64/native/` or `runtimes/iossimulator-arm64/native/` and the .NET for iOS SDK's automatic static linking instead.

Every runtime bundles dav1d 1.5.4 as the AV1 decoder. The static sets ship `libdav1d.a` (`dav1d.lib` on Windows) next to the FFmpeg archives; the Android, macOS, and Windows shared libraries link dav1d statically into the FFmpeg codec library.

macOS and Windows bundle libopus 1.6.1 for Opus encoding, embedded in shared FFmpeg libraries and supplied as `libopus.a` or `opus.lib` for static linking. These desktop builds include `hwdownload`, `hwupload`, `scale`, `format`, `aformat`, and `aresample`; hardware scaling uses `scale_vt` on macOS and `scale_d3d11` on Windows.

The HLS and DASH demuxers and file protocol are enabled on every runtime for applications that provide manifests, playlists, and segment resources through `AVFormatContext.io_open`. FFmpeg networking remains disabled; HTTP transport belongs to the consuming application. DASH manifest parsing is provided by libxml2 2.15.3, which is linked statically into shared builds and shipped as `libxml2.a` (`xml2.lib` on Windows) with static builds.

PGS (Blu-ray bitmap) subtitles are enabled on every runtime through the `pgssub` decoder, including embedded PGS tracks in Matroska and MPEG-TS. The `sup` demuxer also supports standalone `.sup` subtitle files.

## Photo formats

The common still-image formats are enabled on every runtime:

| Format | Demuxer | Decoder |
| --- | --- | --- |
| JPEG | `image2`, `jpeg_pipe` | `mjpeg` |
| PNG / APNG | `image2`, `png_pipe`, `apng` | `png`, `apng` |
| WebP (still and animated) | `image2`, `webp_pipe`, `webp_anim` | `webp` |
| TIFF | `image2`, `tiff_pipe` | `tiff` |
| AVIF | `mov` (HEIF item support) | `libdav1d` |
| HEIC | `mov` (HEIF item support) | `hevc` |
| JPEG XL (still and animated) | `jpegxl_pipe`, `jpegxl_anim` | `libjxl`, `libjxl_anim` |

JPEG XL comes from libjxl 0.12.0, pinned to `fd6618be4dd5c6397e917743a71987ba842f51a6`
on upstream's `v0.12.x` branch, and built from the `libjxl` submodule the
same way dav1d is. It is enabled on `android-arm64`, `android-x64`, `osx-arm64`, `ios-arm64`, `iossimulator-arm64`, `win-x64`, `win-arm64`
and the multi-threaded browser-wasm variant. It is **not** available in the
single-threaded browser-wasm variant: libjxl's parallel runner is `std::thread`
based and FFmpeg always creates it with `av_cpu_count()` workers, which aborts in
an Emscripten module built without pthreads.

Still JPEG XL encoding is enabled through `libjxl` on the same targets, using the already bundled dependencies. No new software HEVC/AV1 codec libraries are included. Android enables every MediaCodec encoder counterpart provided for its enabled decoders: H.264, HEVC, MPEG-4, VP8, VP9, and AV1. Apple VideoToolbox and Windows Media Foundation encoders remain enabled without additional vendor SDKs.

zlib is required by the PNG decoder. Android, macOS, and iOS use the platform copy;
browser-wasm uses the Emscripten `zlib` port and ships the resulting `libz.a`
next to the FFmpeg archives, so consuming projects do not have to enable the
port themselves. Windows builds the pinned zlib submodule with the same MSVC ABI
as FFmpeg, embeds it into shared libraries, and ships `zlib.lib` for static linking.

### Remaining symbol risks

Inspection of the available Android FFmpeg and Android/Linux Photos shared
artifacts found no exported private skcms, Brotli, Highway, dav1d, libxml2,
JPEG or zlib definitions. LCMS intentionally exports its public API. These
checks do not imply that all LibRaw internals or C++ runtime symbols are hidden,
and shared-library boundaries do not isolate the separately shipped static archives.
macOS artifacts were not inspected on the Linux development host.

The remaining candidates below are not resolved:

| Dependency | Evidence and recommended follow-up |
| --- | --- |
| LibRaw shared libraries | Both Android ABIs export 55 symbols in the inspected C++ runtime families, including `__cxa_*`. Android and Linux also expose generic internals such as `J`, `JS` and `default_data_callback`. Restrict exports to the supported LibRaw API and localize the embedded runtime with an export map / `--exclude-libs`; do not macro-rename the C++ runtime ABI. |
| zlib | Existing FFmpeg and Photos wasm archives share 113 global definitions, including internal helpers. Prefer one explicitly shared, compatible archive, or namespace Photos' private copy and embed it into LibRaw. Ordinary lazy archive linking may silently select one implementation; whole-archive linking can report duplicates. |
| Brotli | libjxl's three archives expose `Brotli*` plus helpers such as `AttachPreparedDictionary`. A private prefix covering all definitions, followed by merging into libjxl, is worthwhile when co-linking another Brotli consumer. |
| Highway | `libhwy.a` exposes the C++ `hwy::` namespace. Different statically linked versions can collide; isolate the namespace consistently in Highway and libjxl before optionally merging. |
| macOS static JPEG | Photos still ships an unprefixed ABI 80 `libjpeg.a`. Apply the same private-prefix strategy as wasm before co-linking another JPEG ABI. |
| libxml2 / dav1d | Separate static archives expose `xml*` / `html*` / `dav1d_*` and internal definitions. Candidates for private namespacing and merging if another consumer brings its own versions; no second copy was verified here. |
| LCMS | The static archive also exposes internal helpers such as `IsIdentity`. Preserve the public `cms*` API used by Photos consumers; consider hiding or prefixing internals rather than blindly merging/renaming the public library. |

Merging archives alone does not prevent static symbol collisions. Private
dependencies need renamed definitions **and references**, or consumers must
deliberately share one compatible implementation. A symbol-name overlap is a
risk, not proof that a particular application's final link currently fails.

## Publish

Push a tag named `ffmpeg-v<package-version>`. The workflow builds each platform, then a final job merges the artifacts and publishes a GitHub release for that tag with the `LightStudio.Ffmpeg` NuGet package attached. Manual dispatch with `publish=true` creates the same versioned release; otherwise it only uploads workflow artifacts. For version 9.0.2.1:

```bash
git tag ffmpeg-v9.0.2.1
git push origin ffmpeg-v9.0.2.1
```

The workflow can also be run manually with a NuGet package version from the Actions tab.

## Consume

After publishing the generated package or configuring a local NuGet feed:

```bash
dotnet add package LightStudio.Ffmpeg --version 9.0.2.1
```

### Android, macOS, and Windows

The shared libraries are deployed by the .NET SDK from `runtimes/<rid>/native`; static linking is opt-in. Generate the managed API with the NativeBindings toolkit from the package's exact-build headers and profiles, with `NativeBindingsStatic=false` for shared imports. See the [NativeBindings example](package/ffmpeg/README.md#nativebindings) for the project properties and `[Include]` declarations. The macOS binaries target macOS 11.0 or later, the Android build script defaults to API 21 (the publishing workflow selects API 35), and Windows targets Windows 10 or later.

### iOS ARM64

All four packages support iOS ARM64 devices and simulators with static archives
only, targeting iOS 15.0 by default. Their `.a` files live under
`runtimes/ios-arm64/native/` or `runtimes/iossimulator-arm64/native/` for
automatic linking by .NET for iOS, without custom iOS linking targets or the
desktop static opt-in properties. Intel simulator RIDs are not included. Use static
`__Internal` bindings; for FFmpeg, set `NativeBindingsStatic=true` and select the
matching RID profile. Supply the system libraries/frameworks listed in each
package README. ONNX includes upstream's `net9.0-ios18.0` managed bindings.

Build on macOS with full Xcode and the iPhoneOS/iPhoneSimulator SDKs; set
`IPHONEOS_DEPLOYMENT_TARGET` to override the minimum for both targets:

```sh
bash scripts/build-ffmpeg-osx-arm64.sh ios-arm64
bash scripts/build-photos.sh ios-arm64
bash scripts/build-onnx.sh ios-arm64
bash scripts/build-sqlite-vec.sh ios-arm64

bash scripts/build-ffmpeg-osx-arm64.sh iossimulator-arm64
bash scripts/build-photos.sh iossimulator-arm64
bash scripts/build-onnx.sh iossimulator-arm64
bash scripts/build-sqlite-vec.sh iossimulator-arm64
```

Device and simulator archives are built separately and cannot be interchanged.
The iOS builds include the common decoding and demuxing components,
FFmpeg VideoToolbox, and ONNX CoreML, with shared output disabled.
sqlite-vec remains extension-only and requires the application's SQLite engine
to register `sqlite3_vec_init` through `sqlite3_auto_extension`.

### WebAssembly

The package adds the correct archives as `NativeFileReference` items automatically. `WasmEnableThreads=true` selects `static/wasm-mt-em<major>`; otherwise `static/wasm-em<major>` is used. Target frameworks through .NET 10 select `em3` (Emscripten 3.1.69); .NET 11 and newer select `em6` (6.0.2). This is a best-effort compatibility rule, not a guarantee for every workload/toolchain version. No manual `NativeFileReference` in the consuming project is needed.

### Static linking with native AOT

In a project that imports the NativeBindings toolkit:

```xml
<PropertyGroup>
  <RuntimeIdentifier>win-x64</RuntimeIdentifier>
  <PublishAot>true</PublishAot>
  <EnableStaticFfmpeg>true</EnableStaticFfmpeg>
  <AllowUnsafeBlocks>true</AllowUnsafeBlocks>
  <NativeBindingsEnabled>true</NativeBindingsEnabled>
  <NativeBindingsPackageDirectory>$(LightStudioFfmpegPackageRoot)</NativeBindingsPackageDirectory>
  <NativeBindingsProfile>win-x64-static</NativeBindingsProfile>
  <NativeBindingsStatic>true</NativeBindingsStatic>
</PropertyGroup>
<ItemGroup>
  <PackageReference Include="LightStudio.Ffmpeg" Version="9.0.2" />
  <DirectPInvoke Include="__Internal" />
</ItemGroup>
```

Publish for `android-arm64`, `android-x64`, `win-x64`, `win-arm64`, or `osx-arm64`, selecting the matching static profile and declaring the FFmpeg headers with NativeBindings `[Include]` attributes. `NativeBindingsStatic=true` generates `__Internal` imports; `DirectPInvoke` configures direct calls for NativeAOT. `EnableStaticFfmpeg` adds the native archives and platform libraries, and drops the package's shared libraries from static publish output. It is ignored without `PublishAot` and on unsupported RIDs; browser-wasm has its own automatic static selection. Android requires a compatible NativeAOT/native-host toolchain, not ordinary Mono AOT. Its linker inputs localize the FFmpeg archives' symbols and request 16 KB page alignment. See the [package README](package/ffmpeg/README.md) for hardware APIs, linking details, symbol-isolation limits, and LGPL distribution obligations.

## Local builds

All variants build dav1d and libxml2 from their submodules first; JPEG XL variants also build libjxl and LCMS2, and desktop FFmpeg builds also build libopus. cmake, meson and ninja are required. libjxl has large optional nested submodules, so `--recursive` is deliberately avoided; `scripts/fetch-libjxl-dependencies.sh` initializes only its brotli and highway dependencies, plus the repository's LCMS2 submodule.

Each script stages its output under `artifacts/<artifact-name>`. Collect all platform outputs, normally from CI, before packing a complete package.

```bash
git submodule update --init
./scripts/fetch-libjxl-dependencies.sh

# Run both variants with Emscripten 3.1.69, then repeat with 6.0.2 activated.
./scripts/build-ffmpeg-browser-wasm.sh single-threaded   # artifacts/ffmpeg-browser-wasm-em<major>
./scripts/build-ffmpeg-browser-wasm.sh multi-threaded    # artifacts/ffmpeg-MT-browser-wasm-em<major>

# Run on macOS with Xcode command-line tools installed.
./scripts/build-ffmpeg-osx-arm64.sh                      # artifacts/ffmpeg-osx-arm64

# Requires the Android NDK and nasm (nasm assembles the android-x64 target).
# Set ANDROID_NDK_HOME if it is not already exported.
./scripts/build-ffmpeg-android.sh                        # artifacts/ffmpeg-android

dotnet pack package/ffmpeg/LightStudio.Ffmpeg.csproj --output artifacts/packages
```

### Windows FFmpeg builds

Use Visual Studio 2022 or later with MSVC x64/ARM64 tools and a recent Windows SDK,
and MSYS2. Start a fresh x64 Native Tools Command
Prompt for `win-x64`, or an x64_arm64 Cross Tools Command Prompt for `win-arm64`.
Launch MSYS2 from that prompt so it inherits the matching SDK environment:

```cmd
C:\msys64\msys2_shell.cmd -defterm -here -no-start -msys -use-full-path
```

```bash
pacman -S --needed make diffutils pkgconf nasm perl \
  mingw-w64-ucrt-x86_64-clang mingw-w64-ucrt-x86_64-lld \
  mingw-w64-ucrt-x86_64-llvm mingw-w64-ucrt-x86_64-cmake \
  mingw-w64-ucrt-x86_64-meson
export PATH="/usr/bin:/ucrt64/bin:$PATH"
git submodule update --init --depth 1 -- ffmpeg dav1d libjxl libxml2 opus zlib
bash scripts/fetch-libjxl-dependencies.sh
bash scripts/build-ffmpeg-windows.sh win-x64
```

For ARM64, use the matching fresh developer prompt and pass `win-arm64`.
[The build](scripts/build-ffmpeg-windows.sh) stages 18 static `.lib` files,
7 versioned FFmpeg DLLs, public headers, and configuration evidence under
`artifacts/ffmpeg-win-<arch>`. Like macOS, shared libraries embed dav1d, JPEG XL,
libxml2, and libopus; Windows also embeds zlib and the MSVC runtime. FFmpeg's MSVC
toolchain requires separate static and shared build passes, both using the same
features and static dependencies. Shared import libraries are not staged over
the static archives. Configuration evidence for the shared pass is in
`build-info/shared`.
`FFMPEG_BUILD_JOBS` controls parallelism; `FFMPEG_REUSE_DEPS=1` reuses dependencies
from the same target/toolchain during local FFmpeg iterations.

The Windows builds use FFmpeg's official MSVC toolchain support with clang-cl and
`/MT`; [BtbN's LGPL builds](https://github.com/BtbN/FFmpeg-Builds) are the licensing
and feature reference. Format support follows macOS, with D3D11VA decoding and
Media Foundation encoding. FFmpeg's available assembly paths, runtime CPU
detection, and JPEG XL's AVX-512 variants are enabled. Configure checks reject
missing hardware APIs, key formats, assembly support, or a non-LGPL configuration.

CI cross-builds both architectures on `windows-2022` and uploads their artifacts
for packing. Runtime execution and hardware compatibility are not checked after building.

The sibling desktop project's local experiment is selected at publish time:

```powershell
dotnet publish ../LightPlayer/src/LightStudio.LightPlayer.Desktop -c Release -r win-x64 -p:LocalFfmpegLibraryDir="$PWD/artifacts/ffmpeg-win-x64"
```

Use the ARM64 RID and artifact directory together for an ARM64 publish. The
property selects static bindings and direct P/Invokes without bundling BtbN DLLs.

## sqlite-vec Builds

[The sqlite-vec workflow](.github/workflows/sqlite-vec.yml) independently builds
`linux-x64`, `linux-arm64`, `win-x64`, `win-arm64`, `osx-x64`, `osx-arm64`,
`ios-arm64`, `iossimulator-arm64`, `android-x64`, `android-arm64`, and both `browser-wasm` threading variants.
Desktop and Android RIDs contain shared and static vec0; iOS contains static
vec0. Android also includes our own shared and static SQLite 3.50.4 libraries.
WASM has vec0 and our own SQLite 3.50.4 static archives for Emscripten 3.1.69 and 6.0.2, selected through `NativeFileReference` according
to `WasmEnableThreads` and the target framework (.NET <= 10: `em3`, >= 11: `em6`).
All outputs include licenses and build metadata. The package does not depend
on LightStudio.Onnx or ship managed bindings. Desktop/iOS consumers supply
their own SQLite engine; Android/WASM consumers can use the bundled engine. All consumers
supply their own managed provider and register `sqlite3_vec_init`.

Desktop/Android builds stage both library types together. Their static archives
are packaged under `static/<rid>/`; Native AOT consumers opt in with
`EnableStaticSqliteVec=true` and `PublishAot=true`, following Photos. Windows
static archives use the MSVC ABI and `/MT`. Android static linking includes both
vec0 and SQLite; its shared libraries are omitted from static publish output.
Shared deployment remains the default.

The standard SQLite extension API also works with Windows WinSQLite; no
`winsqlite3.lib` link or separate Windows variant is necessary. See
[the package README](package/sqlite-vec/README.md) for provider selection,
native filenames, local builds, and platform requirements.

```sh
bash scripts/build-sqlite-vec.sh linux-x64
dotnet pack package/sqlite-vec/LightStudio.sqlite-vec.csproj -c Release -o artifacts/packages
```

Release Linux builds use the pinned
[Ubuntu 24.04 build image](scripts/sqlite-vec-linux.Dockerfile), not the host
toolchain. A complete package includes all ten native artifacts and all four WASM
variants. Build these with `bash scripts/build-sqlite-vec.sh browser-wasm` and
`bash scripts/build-sqlite-vec.sh browser-wasm-mt` under each supported SDK. Select
local subsets with `SqliteVecRuntimeIdentifiers` and use a prerelease version.
Tags `sqlite-vec-v<version>`
publish GitHub releases with the complete package attached after all build jobs
pass. Manual dispatch with `publish=true` also publishes a release.

## ONNX Builds

[The ONNX workflow](.github/workflows/onnx.yml) builds `linux-x64`, `linux-arm64`,
`android-arm64`, `android-x64`, `osx-x64`, `osx-arm64`, `ios-arm64`, and `iossimulator-arm64`.
It uses external Dawn/Vulkan on Linux and Android, and CoreML on macOS and iOS. Provider
registration remains integrated in the runtime library; the standalone
`LightStudio.WebGPU` package supplies `libwebgpu_dawn.so` through an exact-version
dependency. ONNX downloads the selected WebGPU NuGet from its GitHub release and
compiles only the matching headers and proc dispatch sources, without fetching
or building Dawn. CoreML uses Apple system APIs. WebGPU also provides ABI-specific
public C headers and hash-validated NativeBindings profiles for non-ONNX use.
The NuGet contains the complete upstream managed assemblies; consumers need no Microsoft ONNX
NuGet references. WebGPU selection on Linux and Android uses the standard
`SessionOptions.AppendExecutionProvider("WebGPU", options)` API with the host's
matching `dawnProcTable` pointer. Select macOS CoreML with
`SessionOptions.AppendExecutionProvider("CoreML", options)`; see the
[package README](package/onnx/README.md) for provider options and priority.

Sources are downloaded at a verified upstream commit into `artifacts/build`.
Linux release builds use the pinned
[Ubuntu 24.04 image](scripts/onnx-linux.Dockerfile) and target glibc 2.39.
Android builds use NDK r28c and default to API 27 with 16 KB page alignment.
macOS and iOS target 15.0. iOS builds are static only.

```sh
export WEBGPU_PACKAGE_VERSION=20260818.211311.0
bash scripts/build-onnx.sh linux-x64
dotnet pack package/onnx/LightStudio.Onnx.csproj -c Release -o artifacts/packages \
  -p:LightStudioWebGPUVersion="$WEBGPU_PACKAGE_VERSION" \
  --source "$PWD/artifacts/build/webgpu-packages/$WEBGPU_PACKAGE_VERSION" \
  --source https://api.nuget.org/v3/index.json
```

Collect all eight ONNX outputs for a complete ONNX package.
Each build stages only `onnx-<rid>` artifacts.
Use the pinned Linux Docker build for release-compatible binaries. Select local
subsets with `OnnxRuntimeIdentifiers`; they are not full releases.
Tags named `onnx-v<version>` publish GitHub releases with only the ONNX package
attached after all build jobs succeed. Manual dispatch with `publish=true` also
publishes a release. The manual `webgpu_package_version` input selects WebGPU for
both compilation and the exact NuGet dependency. It defaults to the current Dawn
pin, `20260818.211311.0`, regardless of release availability. Missing releases fail
without falling back to a source build or another version.

## WebGPU Builds

[The WebGPU workflow](.github/workflows/webgpu.yml) independently builds Dawn for
`linux-x64`, `linux-arm64`, `android-arm64`, and `android-x64` with Vulkan;
`osx-arm64`, `ios-arm64`, and `iossimulator-arm64` with Metal; and
`win-x64` and `win-arm64` with D3D12. Apple x64 is not built. Its own
[Dawn pin](package/webgpu/Dawn.props) records the upstream tag, commit, and archive
checksum.

```sh
bash scripts/build-webgpu.sh linux-x64
dotnet pack package/webgpu/LightStudio.WebGPU.csproj -c Release -o artifacts/packages \
  -p:WebGPURuntimeIdentifiers=linux-x64
```

Collect all nine `webgpu-<rid>` outputs for a complete WebGPU package. iOS uses
static archives; macOS and Windows use shared libraries. Release
Linux builds use the pinned [Ubuntu image](scripts/webgpu-linux.Dockerfile).
The default NuGet version is Dawn's upstream `20260818.211311`, normalized to
`20260818.211311.0`. Manual `package_version` or local `-p:PackageVersion=...`
overrides the package version without changing the source pin. Tags named
`webgpu-v<package-version>` publish only WebGPU; manual `publish=true` does the
same. See the [WebGPU README](package/webgpu/README.md) for standalone NativeBindings
use and the exported ONNX-compatible Dawn API layout.

Browser WASM is intentionally omitted: upstream's asynchronous browser WebGPU
bridge does not supply a supported threaded integration for the full synchronous
.NET API. See the [ONNX README](package/onnx/README.md) for the platform rationale.

## Photos Builds

iOS ARM64 devices and simulators use the same library features as macOS with static output only:
`libraw.a`, `liblcms2.a`, `libjpeg.a`, `libz.a`, `libjxrglue.a` and `libjpegxr.a`. The Apple-hosted workflow
also builds this target; its SDK and consumption requirements are described above.

`LightStudio.Photos` is independent of FFmpeg. It includes shared and static libraries for `android-arm64`, `android-x64`, `linux-x64`, `linux-arm64`, `win-x64`, `win-arm64`, `osx-arm64` and `osx-x64`, and separate single/multi-threaded wasm32 archives. libjpeg-turbo 3.1.3 and zlib 1.3.2 enable lossy JPEG and floating-point deflate DNG decoding. They are embedded into LibRaw's shared libraries and shipped as `libjpeg.a`/`libz.a` beside `libraw.a`/`liblcms2.a` for native static consumers, or `jpeg.lib`/`zlib.lib` beside `libraw.lib`/`liblcms2.lib` for Windows. jxrlib 1.1 adds JPEG XR via `libjxrglue` and `libjpegxr`, with shared and static libraries matching each platform. Wasm embeds a namespaced JPEG implementation into `libraw.a` and ships `libraw.a`, `liblcms2.a`, `libz.a`, `libjxrglue.a` and `libjpegxr.a`. The [package README](package/photos/README.md) documents P/Invoke names, `WasmEnableThreads`, `EnableStaticPhotos`, supported formats and licenses.

Wasm retains JPEG ABI 80 internally. The build derives a `lightstudio_photos_` symbol prefix map from the complete JPEG archive, recompiles JPEG and LibRaw with it, then merges their archive members with `emar`. Merging alone or hidden visibility does not isolate symbols in a static wasm link. Emscripten 3.1.69 and 6.0.5's `llvm-objcopy` do not support wasm symbol localization/renaming; `--localize-hidden` leaves the global JPEG symbols unchanged. No JPEG ABI downgrade or pinned source changes are needed.

The [Photos workflow](.github/workflows/photos.yml) uses `ubuntu-22.04`, the oldest supported hosted Ubuntu image, for Linux x64, Windows cross-builds, Android, wasm and packing. Linux arm64 builds natively on `ubuntu-22.04-arm`. Both Linux architectures compile inside pinned architecture-specific manylinux2014 (CentOS 7, glibc 2.17) containers; the host runner does not set the binary's glibc baseline. The baseline containers are build environments, not a recommendation to deploy an end-of-life OS.

macOS uses `macos-14`, as the existing FFmpeg macOS job does, and explicitly targets macOS 11.0. That runner is deprecated upstream and will need replacement when retired; the deployment target can remain 11.0. Intel binaries are cross-built on Apple silicon. Windows x64 shared libraries use the MinGW Win32-thread toolchain on Linux.

Windows ARM64 shared libraries use [LLVM-MinGW](https://github.com/mstorsjo/llvm-mingw), because GCC MinGW does not target Windows on ARM. Compilation stays on `ubuntu-22.04`, using the SHA-256-pinned 20260908 UCRT toolchain. All dependencies are built with the same LLVM-MinGW toolchain, avoiding incompatible GCC/LLVM static objects. The C++ runtime, JPEG and zlib are embedded in LibRaw, and the package includes the required toolchain notices.

Windows static libraries build separately on `windows-2022`, using the same clang-cl/MSVC ABI and `/MT` runtime convention as FFmpeg. [The static build script](scripts/build-photos-windows-static.sh) uses CMake for JPEG, zlib, LCMS and jxrlib and LibRaw's upstream MSVC static target, without DLL import/export definitions. Its six `.lib` files are staged under `artifacts/photos-win-<arch>-static` and packed under `static/win-<arch>`. MinGW supplies the separate DLL builds. `EnableStaticPhotos=true` with `PublishAot=true` selects the static libraries and removes the Photos DLLs from publish output.

Android follows FFmpeg's SDK setup and combined artifact pattern, using NDK r28c (`28.2.13676358`), API 21, and both 64-bit ABIs. Local builds use `/usr/lib/android-ndk` by default. Artifacts have 16 KB page alignment and do not require `libc++_shared.so`.

Initialize only the required sources, then run the targets available on your host:

```bash
git submodule update --init libraw lcms2 libjpeg-turbo zlib jxrlib

# Requires Autotools, CMake, make, pkg-config, GCC/G++, and patchelf.
./scripts/build-photos.sh linux-x64

# Cross-build on x64 with crossbuild-essential-arm64 and patchelf.
# Also works natively on arm64.
./scripts/build-photos.sh linux-arm64

# Reproduce the CI glibc compatibility build; Docker image contains the tools.
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp \
  -v "$PWD:/work" -w /work \
  quay.io/pypa/manylinux2014_x86_64@sha256:493d2032114d757aaa761a9385ad8497f391503bf71acef9abeeb66682ca5d90 \
  ./scripts/build-photos.sh linux-x64

# Debian/Ubuntu MinGW packages: gcc/g++-mingw-w64-x86-64-win32.
./scripts/build-photos.sh win-x64

# Windows ARM64 cross-build on x64 Linux (Ubuntu 22.04 or compatible).
./scripts/setup-photos-llvm-mingw.sh
./scripts/build-photos.sh win-arm64

# Windows static: use MSYS2 with the matching Visual Studio developer environment,
# clang-cl, CMake and Ninja, as in the Windows FFmpeg build instructions above.
bash scripts/build-photos-windows-static.sh win-x64
# For ARM64, start a fresh x64_arm64 developer environment instead.
bash scripts/build-photos-windows-static.sh win-arm64

ANDROID_NDK_HOME=/usr/lib/android-ndk ./scripts/build-photos-android.sh

# Requires Emscripten; CI uses 3.1.69, matching FFmpeg.
./scripts/build-photos.sh browser-wasm
./scripts/build-photos.sh browser-wasm-mt

# On macOS with Xcode and Homebrew autoconf, automake, libtool, pkg-config, cmake.
./scripts/build-photos.sh osx-arm64
./scripts/build-photos.sh osx-x64

# Requires every real platform artifact, normally downloaded from CI.
dotnet pack package/photos/LightStudio.Photos.csproj --output artifacts/packages
```

`PHOTOS_BUILD_JOBS` controls parallelism. Each target rebuilds its own directory under `artifacts/build/photos-*` without modifying the pinned submodule sources.

`LLVM_MINGW_HOME` can point to another LLVM-MinGW installation; the default is the pinned toolchain under `artifacts/toolchains`.

Local arm64 cross-builds inherit the installed toolchain's glibc/C++ sysroot baseline; use CI's native manylinux build for release compatibility. JPEG/zlib are built from the pinned sources rather than taken from the host or NDK.

Push a `photos-v<package-version>` tag (initial version `photos-v0.22.2`) to publish a GitHub release with the complete `.nupkg` attached. Manual dispatch also builds the complete package and publishes a release only with `publish=true`.
