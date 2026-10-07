# LightStudio.sqlite-vec

Native-only [sqlite-vec](https://github.com/asg017/sqlite-vec) 0.1.9 loadable
extensions and Linux/Windows/macOS/Android/iOS/browser-WASM static libraries. The package has **no NuGet
dependencies** and is independent of LightStudio.Onnx. It contains vec0
libraries, our own SQLite 3.50.4 builds for Android and all four WASM variants,
licenses, build metadata, and MSBuild integration. No desktop/iOS SQLite engine,
SQLite source, or managed SQLite binding is shipped.

## Runtimes

| RIDs | Native asset | Minimum platform |
| --- | --- | --- |
| `linux-x64`, `linux-arm64` | `vec0.so`, plus `libvec0.a` in `static/<rid>/` | glibc 2.39 |
| `win-x64`, `win-arm64` | `vec0.dll`, plus `vec0.lib` in `static/<rid>/` | Windows 10/11, matching process architecture |
| `osx-x64`, `osx-arm64` | `vec0.dylib`, plus `libvec0.a` in `static/<rid>/` | macOS 11 |
| `ios-arm64` | `libvec0.a` in `runtimes/ios-arm64/native/` | iOS 15, device only |
| `iossimulator-arm64` | `libvec0.a` in `runtimes/iossimulator-arm64/native/` | iOS 15, ARM64 simulator |
| `android-x64`, `android-arm64` | `libvec0.so` + `libsqlite3.so`, plus `libvec0.a` + `libsqlite3.a` in `static/<rid>/` | Android API 27, 16 KB page compatible |
| `browser-wasm`, single-threaded | `libvec0.a` + `libsqlite3.a` in `static/wasm-em3/` and `static/wasm-em6/` | .NET browser WASM with native linking |
| `browser-wasm`, multithreaded | `libvec0.a` + `libsqlite3.a` in `static/wasm-mt-em3/` and `static/wasm-mt-em6/` | Thread-enabled .NET browser WASM with native linking |

Shared assets live in `runtimes/<rid>/native/`. The .NET SDK selects and deploys them.
The Android filenames have the `lib` prefix required for APK native libraries.
Intel iOS simulators, native 32-bit, and musl RIDs are not included. No AVX/AVX2-only
CPU baseline is imposed.

## SQLite Host

For shared desktop extensions, bring an SQLite engine with extension loading
enabled. Android includes a compatible engine, but can also use an existing one.
Supply the managed bindings of your choice on all platforms. Use SQLite 3.38
or newer for the complete vec0 query features.
The extension is compiled against the ordinary `sqlite3ext.h` interface and
receives SQLite functions through the `sqlite3_api_routines` table. It neither
embeds SQLite nor imports a particular SQLite DLL, so it can be used with an
application's existing compatible engine, including `sqlite3` or `e_sqlite3`.

Android's bundled SQLite is separate from vec0 and is built with
`SQLITE_THREADSAFE=1`, column metadata, FTS5, RTree, and extension loading enabled.
For shared-library use, bindings must target `sqlite3`/`libsqlite3.so`; providers
fixed to `e_sqlite3` need configuration to use this engine. Do not also deploy a
second `libsqlite3.so`. Both shared libraries and the static AOT link flags
support 16 KB pages. SQLite's public-domain notice is included under
`licenses/android-<arch>/sqlite3/`.

**Windows can use the system `winsqlite3.dll`.** No different extension build
or SQLite import library is needed. The system engine must support extension
loading and the SQLite features used by the application.

For Microsoft.Data.Sqlite applications using the Windows system engine, select
`Microsoft.Data.Sqlite.Core` plus `SQLitePCLRaw.bundle_winsqlite3` in the app,
as described in [Microsoft's provider documentation](https://learn.microsoft.com/en-us/dotnet/standard/data/sqlite/custom-versions).
Those are application dependencies, not dependencies of this package.
WinSQLite versions and compile options depend on Windows servicing. If an
older system engine lacks the required features or extension loading, select
a normal SQLite engine in the application instead. No fallback desktop SQLite
engine is added to this package, and neither `winsqlite3.lib` nor `sqlite3.lib`
is linked into vec0.

## Consume

```sh
dotnet add package LightStudio.sqlite-vec --version 0.1.9
```

For a desktop application already using Microsoft.Data.Sqlite, load the native
asset with the explicit entry point `sqlite3_vec_init`:

```csharp
using System.Runtime.InteropServices;
using Microsoft.Data.Sqlite;

string nativeName = OperatingSystem.IsWindows() ? "vec0.dll"
    : OperatingSystem.IsMacOS() ? "vec0.dylib" : "vec0.so";
string extensionPath = Path.Combine(AppContext.BaseDirectory, nativeName);
if (!File.Exists(extensionPath))
{
    extensionPath = Path.Combine(AppContext.BaseDirectory, "runtimes",
        RuntimeInformation.RuntimeIdentifier, "native", nativeName);
}

using var connection = new SqliteConnection("Data Source=:memory:");
connection.Open();
connection.LoadExtension(extensionPath, "sqlite3_vec_init");
using var command = connection.CreateCommand();
command.CommandText = "SELECT vec_version()";
Console.WriteLine(command.ExecuteScalar());
```

SQLite's loader does not use .NET's NuGet probing rules, so pass the resolved
path, not just `vec0`, for RID-less desktop builds. RID-specific publish puts
the selected native asset beside the executable. On Android, load `libvec0.so`
from the app's native-library location using an engine/provider that exposes
extension loading; Android's framework database API is not sufficient. Load
the extension on each connection that uses it. Do not pass an SQLite connection
handle from one engine to another. Only load trusted extension binaries.

### Desktop and Android Native AOT

Static linking is opt-in, following the Photos package's pattern:

```xml
<PropertyGroup>
    <PublishAot>true</PublishAot>
    <RuntimeIdentifier>win-x64</RuntimeIdentifier>
    <EnableStaticSqliteVec>true</EnableStaticSqliteVec>
</PropertyGroup>
<ItemGroup>
    <DirectPInvoke Include="vec0" />
</ItemGroup>
```

Supported RIDs are `linux-x64`, `linux-arm64`, `win-x64`, `win-arm64`,
`osx-x64`, `osx-arm64`, `android-x64`, and `android-arm64`.
With both `EnableStaticSqliteVec=true` and `PublishAot=true`, the package adds
the matching vec0 `NativeLibrary` archive, plus `libsqlite3.a` on Android, and
removes this package's shared libraries from the publish output. Other packages'
native assets are preserved. Without both properties, shared-library deployment
is unchanged, including Android's bundled `libsqlite3.so`.
Windows archives use the MSVC ABI and static CRT (`/MT`).

The `DirectPInvoke` name must match your binding's library name, for example
`DllImport("vec0", EntryPoint = "sqlite3_vec_init")`. Supply your own SQLite
engine on desktop; Android links the bundled engine. On Android, also add
`<DirectPInvoke Include="sqlite3" />` for bindings targeting `sqlite3` and do
not statically link another SQLite engine, including one from a provider bundle.
The package supplies `m` on Linux, and `dl`, `m`, and the 16 KB page-size linker
flag on Android. Register the native `sqlite3_vec_init` function pointer with the engine's
`sqlite3_auto_extension` before opening connections. Registration must retain
a reference to the entry point so the linker includes it. The package does
not register vec0 or provide managed bindings automatically.

Like iOS, these archives use the extension API table, not `SQLITE_CORE`.
SQLite supplies the `sqlite3_api_routines` table when calling the registered
entry point; do not call it with a null API table or use `LoadExtension` for
the static archive. The engine must support auto-extension registration and
SQLite 3.38+ for the complete vec0 query features.

### iOS

The .NET for iOS SDK automatically links `libvec0.a` from
`runtimes/ios-arm64/native/` for devices or
`runtimes/iossimulator-arm64/native/` for ARM64 simulators. No manual archive reference or custom package
linking target is needed. Supply your own SQLite engine and managed bindings.
Register the `sqlite3_vec_init` function pointer with that engine's
`sqlite3_auto_extension` before opening connections; a managed declaration can
use `DllImport("__Internal", EntryPoint = "sqlite3_vec_init")`. The registration
must reference the entry point so the linker retains it. The package does not
register vec0 automatically.

Unlike WASM, this archive retains the extension API table interface and does
not use `SQLITE_CORE`. SQLite supplies the `sqlite3_api_routines` table when it
invokes the registered entry point. Do not call it with a null API table or use
dynamic `LoadExtension` on iOS. Your engine must support auto-extension
registration and SQLite 3.38+ for the complete vec0 query features.

### Browser WASM

For `RuntimeIdentifier=browser-wasm` or `TargetPlatformIdentifier=browser`,
the package adds `NativeFileReference` items for both `libvec0.a` and
`libsqlite3.a` automatically, following the FFmpeg package's variant selection.
Both archives come from the selected directory:

| `WasmEnableThreads` | .NET <= 10 | .NET >= 11 |
| --- | --- | --- |
| unset or `false` | `static/wasm-em3/` | `static/wasm-em6/` |
| `true` | `static/wasm-mt-em3/` | `static/wasm-mt-em6/` |

Use the .NET WASM native-build workload matching your SDK. CI uses Emscripten
3.1.69 for `em3` and 6.0.2 for `em6`, as do FFmpeg and Photos. Framework-major
selection is best-effort, not a guarantee for every workload/toolchain version.
Rebuild with your SDK's Emscripten version if required.
Enable multithreading in the consuming app with:

```xml
<PropertyGroup>
    <WasmEnableThreads>true</WasmEnableThreads>
</PropertyGroup>
```

The bundled SQLite engine uses `SQLITE_THREADSAFE=0` for ST and
`SQLITE_THREADSAFE=1` with `-pthread` for MT. Column metadata, FTS5, and RTree
are enabled; dynamic extension loading is omitted. SQLite's public-domain
notice is included under `licenses/browser-wasm[-mt]-em<major>/sqlite3/`.

Supply managed bindings targeting this engine's `sqlite3_*` symbols, such as
`DllImport("__Internal", EntryPoint = "sqlite3_open")`. Do not also link a
second SQLite engine, including one supplied by a managed provider bundle.
Providers targeting `e_sqlite3` need configuration to use the bundled engine;
this package does not supply aliases or a managed provider. The vec0 archives
are built with `SQLITE_CORE`: they call the bundled engine directly, without
embedding a second copy. Dynamic `LoadExtension` is not supported in the
browser. Register `sqlite3_vec_init` through `sqlite3_auto_extension` before
opening connections, or call `sqlite3_vec_init(database, &error, NULL)` for each
existing connection using its actual native SQLite handle. Registration must
reference the entry point so the native linker retains it. A managed native
call can use `DllImport("__Internal", EntryPoint = "sqlite3_vec_init")`.
The package links both archives but does not register vec0 automatically.

Thread-enabled browser hosting also requires cross-origin isolation
(COOP/COEP headers) and `SharedArrayBuffer` support.

## Build and Publish

Sources and the MIT license are SHA-256-pinned. The SQLite amalgamation archive
provides headers for all builds and `sqlite3.c` for the separate Android and
WASM SQLite libraries; SQLite is never compiled into vec0 itself. Android and
WASM build metadata records the SQLite version, source archive hash, features,
and threading mode.
Native build outputs are staged under `artifacts/sqlite-vec-<rid>/`; WASM
outputs use `artifacts/sqlite-vec-browser-wasm[-mt]-em<major>/`, derived from
the active `emcc` version.
Linux, Windows, macOS, and Android builds produce both shared and static
extensions in the same staging directory. Android also stages `libsqlite3.so`
and `libsqlite3.a`. Windows `vec0.lib` is the static archive, not the
DLL import library; its build output is isolated from the import library.
The generated source copy includes compatibility fixes: the upstream MSVC
ARM64 Hamming-distance fallback accepts a 64-bit argument instead of truncating
it to 32 bits, and WASM32 uses the 64-bit popcount builtin rather than the
32-bit `unsigned long` builtin. The downloaded upstream source remains unchanged.

```sh
bash scripts/build-sqlite-vec.sh linux-x64
bash scripts/build-sqlite-vec.sh win-x64
bash scripts/build-sqlite-vec.sh osx-arm64
bash scripts/build-sqlite-vec.sh android-arm64
bash scripts/build-sqlite-vec.sh ios-arm64
bash scripts/build-sqlite-vec.sh iossimulator-arm64

bash scripts/build-sqlite-vec.sh browser-wasm
bash scripts/build-sqlite-vec.sh browser-wasm-mt

dotnet pack package/sqlite-vec/LightStudio.sqlite-vec.csproj -c Release -o artifacts/packages
```

Run the WASM builds once with Emscripten 3.1.69 activated and once with 6.0.2.
A complete package includes shared and static vec0 for all eight desktop/Android
RIDs, shared and static SQLite for both Android RIDs, both iOS device and ARM64
simulator static archives, and all four WASM outputs. Selecting a desktop or
Android RID packs both its shared and static libraries.
`browser-wasm-mt` is a build variant, not a NuGet RID; selecting `browser-wasm`
always packs both threading modes for both SDK majors. For local subset packs,
select RIDs with `SqliteVecRuntimeIdentifiers` and use a prerelease `PackageVersion`.
For multiple RIDs, pass the
semicolon-separated list as an environment property. `SqliteVecArtifactsPath`
can select a different artifact root.

Linux releases build in `scripts/sqlite-vec-linux.Dockerfile`, which pins
Ubuntu 24.04 and is independent of the ONNX build. Run Linux builds on the
matching host architecture; use MSVC C++ tools, CMake, and Ninja on Windows,
Xcode command-line tools on macOS, full Xcode with the iPhoneOS/iPhoneSimulator SDK for iOS, and Android NDK r28c for Android. `IPHONEOS_DEPLOYMENT_TARGET` overrides the iOS minimum of 15.0 for both device and simulator. Set
`ANDROID_NDK_HOME` for Android builds. `SQLITE_VEC_BUILD_DIR` isolates a build
tree; `SQLITE_VEC_ARTIFACTS_DIR` changes the staging root.
Windows builds use Ninja with `cl` from an MSVC developer environment initialized
for the requested x64 or ARM64 target before starting Bash. The workflow sets
this up automatically. If a local build tree used a Visual Studio generator,
select a fresh tree with `SQLITE_VEC_BUILD_DIR` before retrying with Ninja.
For WASM, activate Emscripten so `emcmake`, `emcc`, and `emar` are
available. The MT archive is compiled with `-pthread`; the ST archive is not.

```sh
docker build -f scripts/sqlite-vec-linux.Dockerfile -t lightstudio-sqlite-vec-build scripts
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp \
    -e SQLITE_VEC_BUILD_DIR=/work/artifacts/build/sqlite-vec-release-linux-x64 \
    -v "$PWD:/work" -w /work lightstudio-sqlite-vec-build \
    bash scripts/build-sqlite-vec.sh linux-x64
```

The independent `sqlite-vec.yml` workflow builds on tags `sqlite-vec-v<version>`
or manual dispatch. Tags build and upload only. Manual dispatch with
`publish=true` publishes the complete package to NuGet.org using
`NUGET_API_KEY`, after all build jobs pass. No post-build validation runs.