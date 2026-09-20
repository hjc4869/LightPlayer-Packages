using System.IO.Compression;
using System.Xml.Linq;

internal static class PackageChecks
{
    internal static void Validate(string packagePath, string runtimeIdentifiers)
    {
        using var archive = ZipFile.OpenRead(packagePath);
        var entries = archive.Entries.ToDictionary(entry => entry.FullName);
        var runtimes = runtimeIdentifiers.Split(';', StringSplitOptions.RemoveEmptyEntries).Order().ToArray();
        var packagedRuntimes = entries.Keys.Where(path => path.StartsWith("runtimes/", StringComparison.Ordinal))
            .Select(path => path.Split('/')[1]).Distinct().Order().ToArray();
        if (!runtimes.SequenceEqual(packagedRuntimes))
        {
            throw new InvalidOperationException($"Unexpected native RID set: {string.Join(", ", packagedRuntimes)}");
        }
        foreach (var runtime in runtimes)
        {
            var nativeName = runtime.StartsWith("osx-", StringComparison.Ordinal) ? "libonnxruntime.dylib" : "libonnxruntime.so";
            Require($"runtimes/{runtime}/native/{nativeName}", 1_000_000);
            Require($"licenses/{runtime}/onnxruntime/ThirdPartyNotices.txt");
            Require($"build-info/{runtime}.txt");
            if (runtime.StartsWith("linux-", StringComparison.Ordinal))
            {
                Require($"licenses/{runtime}/dependencies/dawn-src/LICENSE");
                Require($"licenses/{runtime}/toolchain/GCC-copyright.txt");
                Require($"licenses/{runtime}/toolchain/GPL-3.txt");
            }
        }
        var frameworks = new[] { "netstandard2.0", "net8.0" };
        var packagedFrameworks = entries.Keys.Where(path => path.StartsWith("lib/", StringComparison.Ordinal))
            .Select(path => path.Split('/')[1]).Distinct().Order().ToArray();
        if (!frameworks.Order().SequenceEqual(packagedFrameworks))
        {
            throw new InvalidOperationException($"Unexpected managed framework set: {string.Join(", ", packagedFrameworks)}");
        }
        foreach (var framework in frameworks)
        {
            Require($"lib/{framework}/Microsoft.ML.OnnxRuntime.dll", 100_000);
            Require($"lib/{framework}/Microsoft.ML.OnnxRuntime.pdb");
        }
        Require("licenses/onnxruntime/LICENSE.txt");
        Require("build/LightStudio.Onnx.targets");
        Require("buildTransitive/LightStudio.Onnx.targets");
        if (entries.Keys.Any(path => path.StartsWith("static/", StringComparison.Ordinal) || path.Contains("browser-wasm", StringComparison.Ordinal)))
        {
            throw new InvalidOperationException("Unexpected unsupported static/browser native asset.");
        }
        using var manifestStream = entries["LightStudio.Onnx.nuspec"].Open();
        var manifest = XDocument.Load(manifestStream);
        var dependencies = manifest.Descendants().Where(element => element.Name.LocalName == "dependency")
            .Select(element => element.Attribute("id")!.Value).ToHashSet(StringComparer.OrdinalIgnoreCase);
        if (dependencies.Any(name => name.StartsWith("Microsoft.ML.OnnxRuntime", StringComparison.OrdinalIgnoreCase)) ||
            !dependencies.Contains("System.Numerics.Tensors") || !dependencies.Contains("System.Memory"))
        {
            throw new InvalidOperationException($"Unexpected package dependencies: {string.Join(", ", dependencies)}");
        }
        Console.WriteLine($"PASS: NuGet layout, full managed payload, {runtimes.Length} native RIDs, licenses, and no Microsoft ONNX package dependencies.");

        void Require(string name, long minimumLength = 1)
        {
            if (!entries.TryGetValue(name, out var entry) || entry.Length < minimumLength)
            {
                throw new InvalidOperationException($"Missing or incomplete package asset: {name}");
            }
        }
    }
}