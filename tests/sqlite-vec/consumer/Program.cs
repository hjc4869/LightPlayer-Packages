using System.Buffers.Binary;
using System.IO.Compression;
using System.Runtime.InteropServices;
using System.Xml.Linq;
using Microsoft.Data.Sqlite;

if (args is ["--check-package", var packagePath, var runtimeIdentifiers])
{
    CheckPackage(packagePath, runtimeIdentifiers.Split(';'));
}
else if (args is ["--test-build-info"])
{
    TestBuildInfo();
}
else if (args is ["--probe-winsqlite"])
{
    ProbeWinSqlite(ExtensionPath());
}
else if (args is ["--smoke"])
{
    using var connection = new SqliteConnection("Data Source=:memory:");
    connection.Open();
    connection.LoadExtension(ExtensionPath(), "sqlite3_vec_init");
    using var command = connection.CreateCommand();
    command.CommandText = SmokeSql();
    command.ExecuteNonQuery();
    Console.WriteLine($"PASS: SQLite {connection.ServerVersion}, vec0 scalar functions, bit vectors, KNN, UPDATE, and DELETE.");
}
else
{
    throw new ArgumentException("Use --check-package <nupkg> <semicolon-RIDs>, --test-build-info, --smoke, or --probe-winsqlite.");
}

static string NativeName(string rid) => rid.Split('-')[0] switch
{
    "win" => "vec0.dll",
    "osx" => "vec0.dylib",
    "android" => "libvec0.so",
    "linux" => "vec0.so",
    _ => throw new ArgumentException($"Unsupported RID: {rid}")
};

static string ExtensionPath()
{
    string rid = RuntimeInformation.RuntimeIdentifier;
    string nativeName = NativeName(rid);
    string direct = Path.Combine(AppContext.BaseDirectory, nativeName);
    string nested = Path.Combine(AppContext.BaseDirectory, "runtimes", rid, "native", nativeName);
    return File.Exists(direct) ? direct : File.Exists(nested) ? nested
        : throw new FileNotFoundException($"The NuGet native asset was not deployed for {rid}.");
}

static string SmokeSql() => """
    CREATE TEMP TABLE checks (ok INTEGER NOT NULL CHECK (ok = 1));
    INSERT INTO checks SELECT vec_version() = 'v0.1.9';
    INSERT INTO checks SELECT vec_distance_L2('[1,2,3]', '[1,2,4]') = 1;
    INSERT INTO checks SELECT vec_distance_cosine('[1,0]', '[1,0]') = 0;
    INSERT INTO checks SELECT vec_distance_hamming(vec_bit(x'ffffffffffffffff'), vec_bit(x'0000000000000000')) = 64;
    INSERT INTO checks SELECT vec_distance_hamming(vec_bit(x'00000000ffffffff'), vec_bit(x'0000000000000000')) = 32;
    CREATE VIRTUAL TABLE vectors USING vec0(embedding float[3], label text);
    INSERT INTO vectors(rowid, embedding, label) VALUES
        (1, '[1,2,3]', 'first long metadata label'),
        (2, '[1,2,4]', 'second long metadata label'),
        (3, '[9,9,9]', 'third long metadata label');
    INSERT INTO checks SELECT (
        SELECT group_concat(rowid, ',') FROM (
            SELECT rowid FROM vectors
            WHERE embedding MATCH '[1,2,4]' AND k = 2 ORDER BY distance
        )
    ) = '2,1';
    UPDATE vectors SET embedding = '[1,2,4]' WHERE rowid = 1;
    DELETE FROM vectors WHERE rowid = 2;
    INSERT INTO checks SELECT (SELECT count(*) FROM vectors) = 2;
    INSERT INTO checks SELECT group_concat(rowid) = '1' FROM (
        SELECT rowid FROM vectors
        WHERE embedding MATCH '[1,2,4]' AND k = 1 ORDER BY distance
    );
    """;

static void CheckPackage(string packagePath, string[] rids)
{
    using var archive = ZipFile.OpenRead(packagePath);
    var names = archive.Entries.Select(entry => entry.FullName).ToHashSet(StringComparer.Ordinal);
    Require(names.Count == archive.Entries.Count, "Duplicate archive entries.");
    var manifest = archive.GetEntry("LightStudio.sqlite-vec.nuspec")
        ?? throw new InvalidDataException("Missing package manifest.");
    using var manifestStream = manifest.Open();
    var document = XDocument.Load(manifestStream);
    Require(!document.Descendants().Any(element => element.Name.LocalName == "dependency"),
        "LightStudio.sqlite-vec must have no NuGet dependencies.");
    Require(document.Descendants().Single(element => element.Name.LocalName == "id").Value == "LightStudio.sqlite-vec",
        "Incorrect package ID.");
    string[] artifactRids = rids.SelectMany(rid => rid == "browser-wasm"
        ? new[] { "browser-wasm", "browser-wasm-mt" } : new[] { rid }).ToArray();
    var expectedNative = artifactRids.Select(NativePackagePath).ToHashSet();
    var actualNative = names.Where(name => name.StartsWith("runtimes/", StringComparison.Ordinal)
        || name.StartsWith("static/", StringComparison.Ordinal)).ToHashSet();
    Require(actualNative.SetEquals(expectedNative), "The native assets must match the requested RIDs, including both WASM variants.");
    Require(!names.Any(name => name.StartsWith("lib/", StringComparison.Ordinal)
        || name.StartsWith("ref/", StringComparison.Ordinal)
        || (!expectedNative.Contains(name) && name.EndsWith(".a", StringComparison.OrdinalIgnoreCase))
        || name.EndsWith(".lib", StringComparison.OrdinalIgnoreCase)
        || name.EndsWith(".c", StringComparison.OrdinalIgnoreCase)
        || name.EndsWith(".h", StringComparison.OrdinalIgnoreCase)
        || (!expectedNative.Contains(name) && (name.EndsWith(".dll", StringComparison.OrdinalIgnoreCase)
            || name.EndsWith(".so", StringComparison.OrdinalIgnoreCase)
            || name.EndsWith(".dylib", StringComparison.OrdinalIgnoreCase)))),
        "Unexpected managed library, SQLite engine, source, or static archive.");
    foreach (string rid in artifactRids)
    {
        Require(names.Contains($"licenses/{rid}/sqlite-vec/LICENSE-MIT"), $"Missing license for {rid}.");
        if (rid.StartsWith("android-", StringComparison.Ordinal))
            Require(names.Contains($"licenses/{rid}/toolchain/NOTICE.toolchain"), $"Missing NDK notice for {rid}.");
        var info = archive.GetEntry($"build-info/{rid}.txt")
            ?? throw new InvalidDataException($"Missing build provenance for {rid}.");
        using var reader = new StreamReader(info.Open());
        Require(HasBuildRid(reader, rid), $"Incorrect build RID for {rid}.");
        var native = archive.GetEntry(NativePackagePath(rid))!;
        using var nativeStream = native.Open();
        using var bytes = new MemoryStream();
        nativeStream.CopyTo(bytes);
        CheckArchitecture(bytes.ToArray(), rid);
    }
    Require(names.Contains("build/LightStudio.sqlite-vec.targets")
        && names.Contains("buildTransitive/LightStudio.sqlite-vec.targets"), "Missing platform checks.");
    Console.WriteLine($"PASS: {packagePath}, {artifactRids.Length} native assets, no SQLite engine or NuGet dependencies.");
}

static string NativePackagePath(string rid) => rid switch
{
    "browser-wasm" => "static/wasm/libvec0.a",
    "browser-wasm-mt" => "static/wasm-mt/libvec0.a",
    _ => $"runtimes/{rid}/native/{NativeName(rid)}"
};

static bool HasBuildRid(TextReader reader, string rid)
{
    while (reader.ReadLine() is { } line)
    {
        if (line == $"RID: {rid}")
            return true;
    }
    return false;
}

static void TestBuildInfo()
{
    foreach (string rid in new[] { "win-x64", "win-arm64" })
    {
        foreach (string newline in new[] { "\n", "\r\n", "\r" })
        {
            foreach (string suffix in new[] { "", newline + "SQLite headers: 3.50.4" + newline })
            {
                using var reader = new StringReader($"sqlite-vec 0.1.9{newline}RID: {rid}{suffix}");
                Require(HasBuildRid(reader, rid), $"Build RID rejected for {rid} with {newline.Length}-character line ending.");
            }
            foreach (string invalid in new[] { "RID: linux-x64", $"RID: {rid}-extra", $"Not RID: {rid}", "No RID metadata" })
            {
                using var reader = new StringReader($"sqlite-vec 0.1.9{newline}{invalid}{newline}");
                Require(!HasBuildRid(reader, rid), $"Invalid build RID accepted for {rid}: {invalid}");
            }
        }
    }
    Console.WriteLine("PASS: build RID validation accepts LF/CRLF/CR and unterminated lines, and rejects incorrect or missing RIDs.");
}

static void CheckArchitecture(byte[] bytes, string rid)
{
    Require(bytes.Length > 4096, $"Invalid native library for {rid}.");
    if (rid.StartsWith("browser-wasm", StringComparison.Ordinal))
    {
        Require(bytes.AsSpan(0, 8).SequenceEqual("!<arch>\n"u8), $"Not a static archive: {rid}.");
        return;
    }
    bool arm64 = rid.EndsWith("-arm64", StringComparison.Ordinal);
    if (rid.StartsWith("win-", StringComparison.Ordinal))
    {
        Require(bytes[0] == 'M' && bytes[1] == 'Z', $"Not a PE library: {rid}.");
        int offset = BinaryPrimitives.ReadInt32LittleEndian(bytes.AsSpan(60));
        Require(offset >= 64 && offset <= bytes.Length - 6, $"Invalid PE offset: {rid}.");
        Require(BinaryPrimitives.ReadUInt32LittleEndian(bytes.AsSpan(offset)) == 0x00004550,
            $"Invalid PE signature: {rid}.");
        Require(BinaryPrimitives.ReadUInt16LittleEndian(bytes.AsSpan(offset + 4)) == (arm64 ? 0xaa64 : 0x8664),
            $"Wrong PE architecture: {rid}.");
    }
    else if (rid.StartsWith("osx-", StringComparison.Ordinal))
    {
        Require(BinaryPrimitives.ReadUInt32LittleEndian(bytes) == 0xfeedfacf, $"Not a 64-bit Mach-O library: {rid}.");
        Require(BinaryPrimitives.ReadUInt32LittleEndian(bytes.AsSpan(4)) == (arm64 ? 0x0100000c : 0x01000007),
            $"Wrong Mach-O architecture: {rid}.");
    }
    else
    {
        Require(bytes.AsSpan(0, 4).SequenceEqual(new byte[] { 0x7f, 0x45, 0x4c, 0x46 })
            && bytes[4] == 2 && bytes[5] == 1, $"Not a little-endian ELF64 library: {rid}.");
        Require(BinaryPrimitives.ReadUInt16LittleEndian(bytes.AsSpan(18)) == (arm64 ? 183 : 62),
            $"Wrong ELF architecture: {rid}.");
    }
}

static void ProbeWinSqlite(string extensionPath)
{
    Require(OperatingSystem.IsWindows(), "The WinSQLite probe must run on Windows.");
    if (!NativeLibrary.TryLoad(Path.Combine(Environment.SystemDirectory, "winsqlite3.dll"), out nint library))
    {
        Console.WriteLine("WinSQLite is unavailable; use application-provided normal SQLite.");
        return;
    }
    nint database = 0;
    try
    {
        var version = Export<WinSqlite.Version>(library, "sqlite3_libversion");
        var compileOption = Export<WinSqlite.CompileOption>(library, "sqlite3_compileoption_used");
        Console.WriteLine($"WinSQLite version: {Marshal.PtrToStringUTF8(version())}; OMIT_LOAD_EXTENSION={compileOption("OMIT_LOAD_EXTENSION")}");
        if (compileOption("OMIT_LOAD_EXTENSION") != 0
            || !NativeLibrary.TryGetExport(library, "sqlite3_load_extension", out _)
            || !NativeLibrary.TryGetExport(library, "sqlite3_enable_load_extension", out _))
        {
            Console.WriteLine("WinSQLite cannot host loadable extensions; use application-provided normal SQLite.");
            return;
        }
        Require(Export<WinSqlite.Open>(library, "sqlite3_open") (":memory:", out database) == 0, "WinSQLite open failed.");
        var enable = Export<WinSqlite.Enable>(library, "sqlite3_enable_load_extension");
        if (enable(database, 1) != 0)
        {
            Console.WriteLine("WinSQLite extension loading is disabled by this Windows build; use normal SQLite.");
            return;
        }
        nint error;
        int result;
        try
        {
            result = Export<WinSqlite.Load>(library, "sqlite3_load_extension")
                (database, extensionPath, "sqlite3_vec_init", out error);
        }
        finally
        {
            enable(database, 0);
        }
        CheckNativeResult(result, error, library);
        result = Export<WinSqlite.Exec>(library, "sqlite3_exec")(database, SmokeSql(), 0, 0, out error);
        CheckNativeResult(result, error, library);
        Console.WriteLine("PASS: system winsqlite3.dll hosts the unmodified SQLite-extension ABI, including vec0 queries.");
    }
    catch (Exception exception) when (exception is EntryPointNotFoundException or InvalidDataException)
    {
        Console.WriteLine($"WinSQLite is not a compatible vec0 host: {exception.Message} Use normal SQLite.");
    }
    finally
    {
        if (database != 0)
            Export<WinSqlite.Close>(library, "sqlite3_close")(database);
        NativeLibrary.Free(library);
    }
}

static TDelegate Export<TDelegate>(nint library, string name) where TDelegate : Delegate
    => Marshal.GetDelegateForFunctionPointer<TDelegate>(NativeLibrary.GetExport(library, name));

static void CheckNativeResult(int result, nint error, nint library)
{
    string? message = Marshal.PtrToStringUTF8(error);
    if (error != 0)
        Export<WinSqlite.Free>(library, "sqlite3_free")(error);
    Require(result == 0, $"WinSQLite error {result}: {message}");
}

static void Require(bool condition, string message)
{
    if (!condition)
        throw new InvalidDataException(message);
}

internal static class WinSqlite
{
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    internal delegate nint Version();
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    internal delegate int CompileOption([MarshalAs(UnmanagedType.LPUTF8Str)] string name);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    internal delegate int Open([MarshalAs(UnmanagedType.LPUTF8Str)] string filename, out nint database);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    internal delegate int Enable(nint database, int enabled);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    internal delegate int Load(nint database, [MarshalAs(UnmanagedType.LPUTF8Str)] string filename,
        [MarshalAs(UnmanagedType.LPUTF8Str)] string entryPoint, out nint error);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    internal delegate int Exec(nint database, [MarshalAs(UnmanagedType.LPUTF8Str)] string sql,
        nint callback, nint context, out nint error);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    internal delegate int Close(nint database);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    internal delegate void Free(nint memory);
}