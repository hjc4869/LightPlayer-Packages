# LightStudio.Onnx

ONNX Runtime 1.30.0 with the complete upstream .NET managed API, WebGPU on Linux
and Android through the transitive `LightStudio.WebGPU` dependency, and CoreML
on macOS and iOS. Add only `LightStudio.Onnx`;
do not also reference
`Microsoft.ML.OnnxRuntime`, `.Managed`, or `.EP.WebGpu`.

On Linux or Android, enable WebGPU explicitly with a matching host-owned
`DawnProcTable` pointer:

```csharp
using System;
using System.Collections.Generic;
using System.Globalization;
using Microsoft.ML.OnnxRuntime;

static InferenceSession CreateWebGpuSession(string modelPath, IntPtr dawnProcTable)
{
    if (dawnProcTable == IntPtr.Zero)
        throw new ArgumentException("A matching Dawn proc table is required.", nameof(dawnProcTable));

    using var options = new SessionOptions();
    options.AppendExecutionProvider("WebGPU", new Dictionary<string, string>
    {
        ["dawnProcTable"] = dawnProcTable.ToInt64().ToString(CultureInfo.InvariantCulture),
        ["preferredLayout"] = "NHWC"
    });
    return new InferenceSession(modelPath, options);
}
```

The native host supplies the table, for example through `dawn::native::GetProcs()`
from the matching Dawn implementation. Its version and function pointers must
match the selected `LightStudio.WebGPU` package. Keep the table and implementation
alive until all ONNX sessions and GPU work are released. The package does not
provide managed ownership wrappers or automatically create a proc table.
Registration without `dawnProcTable` fails in external-Dawn mode. See the
[upstream contract](https://github.com/microsoft/onnxruntime/blob/main/docs/WebGPU_External_Dawn.md).

The standard namespaces, `InferenceSession`, `DenseTensor<T>`, `OrtValue`, I/O
binding, metadata, and profiling APIs are preserved. Accelerator selection is
explicit; an unconfigured session uses CPU. Unsupported operators may fall back
to CPU. Use `options.AddSessionConfigEntry("session.disable_cpu_ep_fallback", "1")`
when CPU fallback must be rejected. WebGPU graph capture is opt-in and requires
static shapes. Native training, CUDA, and ROCm are not enabled.

## Platform Providers

Android includes only CPU and WebGPU execution providers. Enable WebGPU with the
API shown above; CPU remains the fallback for unsupported operators.

For macOS, use the generic CoreML API with the unchanged upstream desktop
assemblies. The legacy `AppendExecutionProvider_CoreML` helper is conditional in
upstream managed builds.

```csharp
options.AppendExecutionProvider("CoreML", new Dictionary<string, string>
{
    ["ModelFormat"] = "MLProgram",
    ["MLComputeUnits"] = "ALL"
});
```

CoreML falls back to CPU for unsupported operators by default. Acceleration
depends on device capabilities and operator support; enabling CoreML does not
guarantee GPU or NPU execution.

## Platforms

| RIDs | Execution providers | Requirements |
| --- | --- | --- |
| `linux-x64`, `linux-arm64` | CPU, WebGPU | glibc 2.39 baseline; compatible Vulkan driver/loader for WebGPU |
| `android-arm64`, `android-x64` | CPU, WebGPU | Android 8.1 (API 27) or later; compatible Vulkan driver for WebGPU; .NET 9+ with Android 35+ API targeting |
| `osx-x64`, `osx-arm64` | CPU, CoreML | macOS 15 or later |
| `ios-arm64` | CPU, CoreML (static) | iOS 15 or later; .NET 9+ for iOS with iOS 18+ API targeting |
| `iossimulator-arm64` | CPU, CoreML (static) | ARM64 iOS simulator; same deployment and .NET requirements as devices |

On Linux and Android, this package ships only `libonnxruntime.so`.
The exact-version `LightStudio.WebGPU` dependency supplies `libwebgpu_dawn.so`,
its licenses, and ABI-specific public C headers for standalone WebGPU use.
Both packages use each RID's native directory. WebGPU registration remains integrated in ONNX
Runtime; no plugin registration is required. ONNX compiles the package's API
dispatch sources, not Dawn itself, and does not link `libwebgpu_dawn.so`.
CPU-only sessions do not load Dawn. The native host loads the matching Dawn
implementation for WebGPU; the Android SDK packages both libraries in the app's
native library directory.
The C++ runtime is linked statically on Linux and Android, and Android libraries
use 16 KB page alignment without a `libc++_shared.so` dependency.
The macOS runtime includes CoreML integration using macOS system APIs. The OS,
graphics driver, Vulkan loader (Linux WebGPU), and macOS system C++ runtime remain system prerequisites.
Telemetry is disabled. Standard framework dependencies
`System.Memory` and `System.Numerics.Tensors` remain normal NuGet dependencies.

Managed assets cover .NET Standard 2.0, .NET 8+, and the upstream
`net9.0-android35.0` and `net9.0-ios18.0` bindings. Intel iOS simulators, musl RIDs, and static macOS
linking are not included.

### Android

Build with NDK r28c (`28.2.13676358`) and an Android SDK:

```sh
export ANDROID_HOME=/path/to/android-sdk
export ANDROID_NDK_HOME="$ANDROID_HOME/ndk/28.2.13676358"
bash scripts/build-onnx.sh android-arm64
bash scripts/build-onnx.sh android-x64
```

Local builds also accept `ANDROID_SDK_ROOT` and `ANDROID_NDK_ROOT`; the NDK
defaults to `/usr/lib/android-ndk`. `ANDROID_API` overrides the native minimum
of 27. NuGet selects the Android managed bindings and native libraries
automatically for Android projects.

### iOS

The .NET for iOS SDK automatically links `libonnxruntime.a` from
`runtimes/ios-arm64/native/` for devices or
`runtimes/iossimulator-arm64/native/` for ARM64 simulators. Each archive combines ONNX Runtime and its static
dependencies, with CPU and CoreML enabled as on macOS. No manual archive
reference or custom package linking target is needed. The iOS managed assembly
uses `__Internal` P/Invokes instead of trying to load a dylib. The generic
CoreML API shown above also works on iOS.

Link the system `c++` library and `Foundation` and `CoreML` frameworks through
the app's iOS linker settings. OS frameworks and the C++ runtime are not bundled.
Build with full Xcode using `bash scripts/build-onnx.sh ios-arm64` or
`bash scripts/build-onnx.sh iossimulator-arm64`. The matching iPhoneOS or
iPhoneSimulator SDK is selected automatically. `IPHONEOS_DEPLOYMENT_TARGET`
overrides the native minimum of 15.0 for both. Upstream's
Xcode generator is used with shared-library generation explicitly disabled;
no dynamic framework is built or shipped.

## Browser Decision

`browser-wasm` is intentionally omitted, including both thread flavors. ORT's
browser WebGPU implementation relies on asynchronous JavaScript and Asyncify/JSPI
for adapter creation, device creation, and buffer readback. Its supported ORT Web
API is asynchronous JavaScript, not the synchronous managed `InferenceSession`
API. Shipping archives alone would not provide a supported threaded .NET bridge.
This does not mean that WebGPU or ORT Web generally lack browser threading.

## Sources And Licensing

Native sources are pinned to ONNX Runtime commit
`f2c39fe2f838cf35ce7da92824f5a5e3ee6e88a7`. A small CMake backport enables the
upstream `onnxruntime_DAWN_PREBUILT_DIR` contract without changing that revision.
Other dependencies use ONNX's pinned dependency manifest. Dawn is owned and
released independently by `LightStudio.WebGPU`. The official 1.30.0 managed assemblies are included
unchanged, with no Microsoft ONNX Runtime package dependency in the final NuGet.
ONNX upstream and dependency notices are included under `licenses/`; Dawn's
notices are in `LightStudio.WebGPU`.

Build a native RID with `bash scripts/build-onnx.sh <rid>`. Linux and Android
download the exact `LightStudio.WebGPU` NuGet package from its
`webgpu-v<version>` GitHub release, verify its API hashes, and compile only its
public/generated headers and standalone proc sources using ONNX's toolchain.
There is no source-build fallback. The default is the repository's current Dawn
pin, `20260818.211311.0`, even when that package has not been built or published;
publish the independent WebGPU release first or select an available version.

`WEBGPU_PACKAGE_VERSION` selects the release used by native builds.
`LightStudioWebGPUVersion` must match when packing; it records the exact NuGet
dependency and defaults to the same Dawn pin, independently of ONNX's
`PackageVersion`. For example:

```sh
export WEBGPU_PACKAGE_VERSION=20260818.211311.0
bash scripts/build-onnx.sh linux-x64
dotnet pack package/onnx/LightStudio.Onnx.csproj -c Release -o artifacts/packages \
    -p:OnnxRuntimeIdentifiers=linux-x64 \
    -p:LightStudioWebGPUVersion="$WEBGPU_PACKAGE_VERSION" \
    --source "$PWD/artifacts/build/webgpu-packages/$WEBGPU_PACKAGE_VERSION" \
    --source https://api.nuget.org/v3/index.json
```

Collect all eight ONNX outputs for a complete package; each native build writes
only `artifacts/onnx-<rid>`. `-p:PackageVersion=1.30.0-local.1` overrides the ONNX
version without changing its WebGPU dependency. Local subsets are not the
all-platform release. Standalone WebGPU consumers reference only
`LightStudio.WebGPU`; see its package README for its independent build and
NativeBindings integration.

Use the pinned Linux Dockerfile for release builds; compiling directly on a newer
distribution can raise the glibc requirement. The GitHub Actions workflow builds
all eight RIDs on `onnx-v*` tags or manual dispatch, then packs and uploads only
the complete ONNX package. Manual `webgpu_package_version` selects the released
WebGPU package consistently for native compilation and the NuGet dependency;
blank uses the repository Dawn pin. Tag builds use that pin and attach only
ONNX to a GitHub release for the tag.
Manual dispatch with `publish=true` also publishes
a release tagged `onnx-v<package_version>` using the built-in `GITHUB_TOKEN`;
the default `publish=false` only uploads workflow artifacts.