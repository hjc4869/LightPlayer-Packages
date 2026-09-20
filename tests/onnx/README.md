# ONNX Validation

The package-only consumer checks NuGet contents and the native provider set:
CPU/WebGPU on Linux and CPU/CoreML on macOS. It exercises the DenseTensor and
OrtValue APIs through CPU multiplication inference. `ONNX_TEST_GPU=1` also tests
the platform accelerator: WebGPU on Linux or CoreML on macOS.

Run `bash tests/onnx/build-args.sh` to check provider selection for all four RIDs
without native compilation. The test requires static Dawn/WebGPU only on Linux
and CoreML only on macOS. Native validation requires Dawn licenses only on Linux
and the CoreML export on macOS.

## Reproduce

Build the release-baseline native library:

```sh
docker build -f scripts/onnx-linux.Dockerfile -t lightstudio-onnx-build .
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e JOBS=8 \
  -v "$PWD:/work" -w /work lightstudio-onnx-build \
  bash scripts/build-onnx.sh linux-x64
bash scripts/check-onnx-native.sh linux-x64
ONNX_TEST_GPU=1 bash scripts/test-onnx-package.sh linux-x64 1.30.0-test.3
```

If the local Docker daemon has no bridge network, `--network host` works for the
build and run commands. If switching toolchains, use a separate `ONNX_BUILD_DIR`
inside the container instead of reusing a CMake cache from another toolchain.

## Other Validation

- Linux x64: source build, clean NuGet restore, self-contained publish, DenseTensor
  and OrtValue CPU/GPU inference, and software Vulkan
  smoke all passed. Highest imported glibc version is 2.38; CI enforces <= 2.39.
- Native Linux libraries have no dynamic Dawn or C++ runtime dependency.
- Package checks verify managed payloads, native RID selection, notices, no
  Microsoft ONNX package dependencies, partial-release rejection, browser
  exclusion, and conflicting direct Microsoft ONNX references.
- Linux ARM64 and macOS x64/ARM64 builds are configured in CI but were not
  executed on this Linux workstation. CoreML inference has not been tested here.
  Hosted CI itself has not been dispatched here.
- Workflow and shell scripts pass actionlint 1.7.12 and ShellCheck.

The local packages are explicitly partial prereleases, not the four-RID
release. The release pack requires every native artifact; no placeholder native
assets were used. Nothing was published.

## Browser Exclusion

No browser runtime or performance tests were performed. Source inspection found
that the supported upstream browser path is not a drop-in threaded .NET static
library integration:

- [ORT's WebGPU link configuration](https://github.com/microsoft/onnxruntime/blob/v1.30.0/cmake/onnxruntime_providers_webgpu.cmake)
  requires Asyncify or JSPI for browser `WGPUFuture` operations.
- [ORT's context implementation](https://github.com/microsoft/onnxruntime/blob/v1.30.0/onnxruntime/core/providers/webgpu/webgpu_context.cc)
  waits for adapter/device creation and readback through `WaitAny`.
- [Emdawnwebgpu's browser bridge](https://github.com/google/dawn/blob/v20260818.211311/third_party/emdawnwebgpu/pkg/webgpu/src/library_webgpu.js)
  implements these waits with `Asyncify.handleAsync`; JS glue is required at the
  final application link, not just archives.
- [ORT Web's supported API](https://onnxruntime.ai/docs/tutorials/web/ep-webgpu.html)
  is asynchronous JavaScript. The complete managed API calls the synchronous
  native C API through P/Invoke. Upstream does not provide the managed suspension
  and thread-ownership bridge needed to combine those paths in a stock threaded
  .NET browser application.

Shipping only `static/wasm-mt/*.a` would therefore promise functionality that the
standard .NET host cannot provide through these APIs. Both browser flavors are
omitted under the requested optional-platform rule. This is a limitation of the
requested full-managed integration, not a claim that ORT Web itself cannot use
threaded WebAssembly or browser WebGPU. A custom asynchronous managed/browser
adapter would be a different API/runtime integration project.