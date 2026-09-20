using Microsoft.ML.OnnxRuntime;
using Microsoft.ML.OnnxRuntime.Tensors;

if (args.Length == 3 && args[0] == "--check-package")
{
    PackageChecks.Validate(args[1], args[2]);
    return;
}
var environment = OrtEnv.Instance();
var providers = environment.GetAvailableProviders();
var accelerator = OperatingSystem.IsMacOS() ? "CoreML" : "WebGPU";
var expectedProviders = OperatingSystem.IsMacOS()
    ? new[] { "CPUExecutionProvider", "CoreMLExecutionProvider" }
    : new[] { "CPUExecutionProvider", "WebGpuExecutionProvider" };
Console.WriteLine($"ONNX Runtime: {environment.GetVersionString()}; providers: {string.Join(", ", providers)}");
if (environment.GetVersionString() != "1.30.0" || !providers.Order().SequenceEqual(expectedProviders.Order()))
{
    throw new InvalidOperationException($"Expected ONNX Runtime 1.30.0 with providers: {string.Join(", ", expectedProviders)}.");
}
environment.DisableTelemetryEvents();
var mode = args.Length == 0 ? "--cpu-smoke" : args[0];
if (mode is "--cpu-smoke" or "--gpu-smoke")
{
    var model = File.ReadAllBytes(args.Length > 1 ? args[1] : "artifacts/build/onnxruntime-src/onnxruntime/test/testdata/mul_1.onnx");
    using var options = new SessionOptions { IntraOpNumThreads = 2 };
    if (mode == "--gpu-smoke")
    {
        options.AppendExecutionProvider(accelerator);
        options.AddSessionConfigEntry("session.disable_cpu_ep_fallback", "1");
    }
    using var session = new InferenceSession(model, options);
    var values = new[] { 1f, 2f, 3f, 4f, 5f, 6f };
    var expected = new[] { 1f, 4f, 9f, 16f, 25f, 36f };
    var inputName = session.InputMetadata.Keys.Single();
    var outputName = session.OutputMetadata.Keys.Single();
    var tensor = new DenseTensor<float>(values, new[] { 3, 2 });
    using var results = session.Run(new[] { NamedOnnxValue.CreateFromTensor(inputName, tensor) });
    if (!results.Single().AsTensor<float>().ToArray().SequenceEqual(expected))
    {
        throw new InvalidOperationException("Multiplication inference failed.");
    }
    using var input = OrtValue.CreateTensorValueFromMemory(values, new long[] { 3, 2 });
    using var runOptions = new RunOptions();
    using var ortResults = session.Run(runOptions, new[] { inputName }, new[] { input }, new[] { outputName });
    if (!ortResults.Single().GetTensorDataAsSpan<float>().SequenceEqual(expected))
    {
        throw new InvalidOperationException("OrtValue inference failed.");
    }
    Console.WriteLine($"PASS: {mode}, DenseTensor and OrtValue APIs, package-only native loading.");
    return;
}
throw new ArgumentException("Usage: --cpu-smoke [mul_1.onnx] | --gpu-smoke [mul_1.onnx]");