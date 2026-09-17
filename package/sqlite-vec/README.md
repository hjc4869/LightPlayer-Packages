# LightStudio.sqlite-vec

Native-only [sqlite-vec](https://github.com/asg017/sqlite-vec) 0.1.9 loadable
extensions. The package has **no NuGet dependencies** and is independent of
LightStudio.Onnx. It contains only the vec0 shared library for each RID, plus
licenses, build metadata, and MSBuild platform checks. No SQLite engine, SQLite
amalgamation, static library, or managed SQLite binding is shipped.

## Runtimes

| RIDs | Native asset | Minimum platform |
| --- | --- | --- |
| `linux-x64`, `linux-arm64` | `vec0.so` | glibc 2.39 |
| `win-x64`, `win-arm64` | `vec0.dll` | Windows 10/11, matching process architecture |
| `osx-x64`, `osx-arm64` | `vec0.dylib` | macOS 11 |
| `android-x64`, `android-arm64` | `libvec0.so` | Android API 27, 16 KB page compatible |

Assets live in `runtimes/<rid>/native/`. The .NET SDK selects and deploys them.
The Android filename has the `lib` prefix required for APK native libraries.
Browser WASM, iOS, 32-bit, and musl RIDs are not included. No AVX/AVX2-only
CPU baseline is imposed.

## SQLite Host

Bring an SQLite engine with extension loading enabled and the managed bindings
of your choice. Use SQLite 3.38 or newer for the complete vec0 query features.
The extension is compiled against the ordinary `sqlite3ext.h` interface and
receives SQLite functions through the `sqlite3_api_routines` table. It neither
embeds SQLite nor imports a particular SQLite DLL, so it can be used with an
application's existing compatible engine, including `sqlite3` or `e_sqlite3`.

**Windows can use the system `winsqlite3.dll`.** No different extension build
or SQLite import library is needed. Microsoft's WinSQLite 3.51.1 was checked
under Wine with a diagnostic Windows x64 extension: extension loading was
enabled, and vec0 scalar, bit-vector, KNN, and DELETE checks passed. This is a
host-ABI compatibility check, not validation of the MSVC release binaries on
native Windows. Both Windows CI runners probe their actual system DLL and
also run the mandatory normal-SQLite consumer tests.

For Microsoft.Data.Sqlite applications using the Windows system engine, select
`Microsoft.Data.Sqlite.Core` plus `SQLitePCLRaw.bundle_winsqlite3` in the app,
as described in [Microsoft's provider documentation](https://learn.microsoft.com/en-us/dotnet/standard/data/sqlite/custom-versions).
Those are application dependencies, not dependencies of this package.
WinSQLite versions and compile options depend on Windows servicing. If an
older system engine lacks the required features or extension loading, select
a normal SQLite engine in the application instead. No fallback SQLite engine
is added to this package, and neither `winsqlite3.lib` nor `sqlite3.lib` is
linked into vec0.

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

## Build and Publish

Sources and the MIT license are SHA-256-pinned. The SQLite amalgamation archive
is downloaded for its headers only; `sqlite3.c` is not compiled into vec0.
Build outputs are staged under `artifacts/sqlite-vec-<rid>/`.
The generated source copy includes one compatibility fix: the upstream MSVC
ARM64 Hamming-distance fallback accepts a 64-bit argument instead of truncating
it to 32 bits. The downloaded upstream source remains unchanged.

```sh
bash scripts/build-sqlite-vec.sh linux-x64
bash scripts/check-sqlite-vec-native.sh linux-x64
bash scripts/test-sqlite-vec-package.sh linux-x64 0.1.9-local.1

dotnet pack package/sqlite-vec/LightStudio.sqlite-vec.csproj -c Release -o artifacts/packages
```

The final command requires all eight staged outputs. Local subset packs require
both `SqliteVecAllowPartialPackage=true` and a prerelease `PackageVersion`;
select RIDs with `SqliteVecRuntimeIdentifiers`. For multiple RIDs, pass the
semicolon-separated list as an environment property. `SqliteVecArtifactsPath`
can select a different artifact root.

Linux releases build in `scripts/sqlite-vec-linux.Dockerfile`, which pins
Ubuntu 24.04 and is independent of the ONNX build. Run Linux builds on the
matching host architecture; use Visual Studio 2022 C++ tools on Windows,
Xcode command-line tools on macOS, and Android NDK r28c for Android. Set
`ANDROID_NDK_HOME` for Android builds. `SQLITE_VEC_BUILD_DIR` isolates a build
tree; `SQLITE_VEC_ARTIFACTS_DIR` changes the staging root.

```sh
docker build -f scripts/sqlite-vec-linux.Dockerfile -t lightstudio-sqlite-vec-build scripts
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp \
    -e SQLITE_VEC_BUILD_DIR=/work/artifacts/build/sqlite-vec-release-linux-x64 \
    -v "$PWD:/work" -w /work lightstudio-sqlite-vec-build \
    bash scripts/build-sqlite-vec.sh linux-x64
```

The consumer tests restore from a fresh local feed/cache, inspect the package
and native architectures, exercise missing-input/release/platform guards, and
compare RID-published native bytes against the staged library. Desktop jobs
execute scalar, 64-bit Hamming, KNN, UPDATE, and long-metadata DELETE checks.
Their Microsoft.Data.Sqlite reference provides a test-only SQLite engine and
is never included in LightStudio.sqlite-vec. Android jobs check binaries and
package contents; they do not execute a device test.

The independent `sqlite-vec.yml` workflow builds on tags `sqlite-vec-v<version>`
or manual dispatch. Tags build and upload only. Manual dispatch with
`publish=true` publishes the complete package to NuGet.org using
`NUGET_API_KEY`, after all build and validation jobs pass.