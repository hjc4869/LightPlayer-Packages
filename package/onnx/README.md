# LightStudio.Onnx

ONNX Runtime 1.30.0 with the complete upstream .NET managed API, embedded
Dawn/WebGPU on Linux, and CoreML on macOS. Add only `LightStudio.Onnx`;
do not also reference
`Microsoft.ML.OnnxRuntime`, `.Managed`, or `.EP.WebGpu`.

On Linux, enable WebGPU explicitly:

```csharp
using Microsoft.ML.OnnxRuntime;

using var options = new SessionOptions();
options.AppendExecutionProvider("WebGPU", new Dictionary<string, string>
{
    ["preferredLayout"] = "NHWC"
});
using var session = new InferenceSession("model.onnx", options);
```

The standard namespaces, `InferenceSession`, `DenseTensor<T>`, `OrtValue`, I/O
binding, metadata, and profiling APIs are preserved. Accelerator selection is
explicit; an unconfigured session uses CPU. Unsupported operators may fall back
to CPU. Use `options.AddSessionConfigEntry("session.disable_cpu_ep_fallback", "1")`
when CPU fallback must be rejected. WebGPU graph capture is opt-in and requires
static shapes. Native training, CUDA, and ROCm are not enabled.

## Platform Providers

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
| `osx-x64`, `osx-arm64` | CPU, CoreML | macOS 15 or later |

Dawn is embedded in the Linux runtime library. The macOS runtime includes CoreML
integration using macOS system APIs. The OS, graphics driver, Vulkan loader
(Linux WebGPU), and macOS system C++ runtime remain system prerequisites.
Telemetry is disabled. Standard framework dependencies
`System.Memory` and `System.Numerics.Tensors` remain normal NuGet dependencies.

Managed assets cover .NET Standard 2.0 and .NET 8+. Mobile
platforms, musl RIDs, and static macOS linking are not included.

## Browser Decision

`browser-wasm` is intentionally omitted, including both thread flavors. ORT's
browser WebGPU implementation relies on asynchronous JavaScript and Asyncify/JSPI
for adapter creation, device creation, and buffer readback. Its supported ORT Web
API is asynchronous JavaScript, not the synchronous managed `InferenceSession`
API. Shipping archives alone would not provide a supported threaded .NET bridge.
This does not mean that WebGPU or ORT Web generally lack browser threading.

## Sources And Licensing

Native sources are pinned to ONNX Runtime commit
`f2c39fe2f838cf35ce7da92824f5a5e3ee6e88a7`. Dawn and other dependencies use its
pinned dependency manifest. The official 1.30.0 managed assemblies are included
unchanged, with no Microsoft ONNX Runtime package dependency in the final NuGet.
Upstream and dependency notices are included under `licenses/`.

Build a native RID with `bash scripts/build-onnx.sh <rid>`, then pack after all
four native outputs are present:

```sh
dotnet pack package/onnx/LightStudio.Onnx.csproj -c Release -o artifacts/packages
```

For local testing only, a deliberately partial prerelease can be built with
`-p:OnnxRuntimeIdentifiers=linux-x64 -p:OnnxAllowPartialPackage=true
-p:PackageVersion=1.30.0-local.1`. Such a package is not the all-platform release.

Use the pinned Linux Dockerfile for release builds; compiling directly on a newer
distribution can raise the glibc requirement. The GitHub Actions workflow builds
all four RIDs on `onnx-v*` tags or manual dispatch, validates native dependencies
and .NET consumers, and uploads the complete package. Only manual dispatch with
`publish=true` pushes to NuGet.org using `NUGET_API_KEY`.