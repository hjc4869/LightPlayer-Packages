# LightStudio.Onnx

ONNX Runtime 1.30.0 with the complete upstream .NET managed assemblies and an
embedded Dawn/WebGPU execution provider. Add only `LightStudio.Onnx`; do not also
reference `Microsoft.ML.OnnxRuntime`, `.Managed`, or `.EP.WebGpu`.

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
binding, metadata, and profiling APIs are preserved. WebGPU selection is explicit;
an unconfigured session uses CPU. Unsupported WebGPU operators may fall back to
CPU. Use `options.AddSessionConfigEntry("session.disable_cpu_ep_fallback", "1")`
when fallback must be rejected. Graph capture is opt-in and requires static shapes.
Native training and non-WebGPU accelerator providers are not enabled, just as
training requires a separate native build with the upstream inference package.

## Platforms

| RIDs | Dawn backend | Requirements |
| --- | --- | --- |
| `linux-x64`, `linux-arm64` | Vulkan | glibc 2.39 baseline, compatible Vulkan driver/loader |
| `win-x64`, `win-arm64` | D3D12 | Windows 10/11 with a compatible D3D12 driver |
| `osx-x64`, `osx-arm64` | Metal | macOS 15 or later with a supported Metal device |
| `android-x64`, `android-arm64` | Vulkan | Android API 27 or later with Vulkan support |

Native dependencies, including Dawn, are linked into the runtime library. The OS,
graphics driver, Vulkan loader (Linux/Android), and macOS system C++ runtime remain system
prerequisites. Android uses static libc++ and 16 KB ELF load alignment; Windows
uses static MSVC runtime. Telemetry is disabled. This is not a CUDA, DirectML,
NNAPI, CoreML, or ROCm package. Standard framework dependencies `System.Memory`
and `System.Numerics.Tensors` remain normal NuGet dependencies.

Managed assets cover .NET Standard 2.0, .NET 8+, and .NET 9+ Android. Other mobile
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
eight native outputs are present:

```sh
dotnet pack package/onnx/LightStudio.Onnx.csproj -c Release -o artifacts/packages
```

For local testing only, a deliberately partial prerelease can be built with
`-p:OnnxRuntimeIdentifiers=linux-x64 -p:OnnxAllowPartialPackage=true
-p:PackageVersion=1.30.0-local.1`. Such a package is not the all-platform release.

Use the pinned Linux Dockerfile for release builds; compiling directly on a newer
distribution can raise the glibc requirement. The GitHub Actions workflow builds
all eight RIDs on `onnx-v*` tags or manual dispatch, validates native dependencies
and .NET consumers, and uploads the complete package. Only manual dispatch with
`publish=true` pushes to NuGet.org using `NUGET_API_KEY`.