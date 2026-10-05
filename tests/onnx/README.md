# ONNX Build Notes

Run `bash tests/onnx/build-args.sh` to check provider selection for all four RIDs
without native compilation. The test requires static Dawn/WebGPU only on Linux
and CoreML only on macOS. It intercepts the build command before compilation and
runs in the workflow's pre-build lint job.

## Reproduce

Build the release-baseline native library:

```sh
docker build -f scripts/onnx-linux.Dockerfile -t lightstudio-onnx-build .
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e JOBS=8 \
  -v "$PWD:/work" -w /work lightstudio-onnx-build \
  bash scripts/build-onnx.sh linux-x64
```

If the local Docker daemon has no bridge network, `--network host` works for the
build and run commands. If switching toolchains, use a separate `ONNX_BUILD_DIR`
inside the container instead of reusing a CMake cache from another toolchain.

## Browser Exclusion

The supported upstream browser path is not a drop-in threaded .NET static
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