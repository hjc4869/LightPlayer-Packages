# LightStudio.AvaloniaStatic.Native

Static Avalonia.Native for Avalonia 12 NativeAOT on `osx-x64` and `osx-arm64`,
built independently of SkiaSharp, HarfBuzzSharp, and ANGLE. The default package
version is **12.1.4**.

Sources are pinned to [hjc4869/Avalonia release/12.1.4](https://github.com/hjc4869/Avalonia/tree/release/12.1.4)
in `scripts/avalonia-static-native/sources.json`. The package includes
`libAvaloniaNative.a`, the font pre-initialization object, per-RID provenance,
and upstream notices. macOS 11+ and the platform native SDK are required.

## Consume

```xml
<PropertyGroup>
  <PublishAot>true</PublishAot>
</PropertyGroup>
<ItemGroup>
  <PackageReference Include="LightStudio.AvaloniaStatic" Version="12.1.4" />
  <PackageReference Include="LightStudio.AvaloniaStatic.Native" Version="12.1.4" />
</ItemGroup>
```

The graphics package is separately versioned and does not depend on Avalonia.
This Native package requires exact versions of **Avalonia** and
**Avalonia.Native**, both matching its own NuGet package version. Use the same
version for other managed Avalonia packages, including Avalonia.Desktop.

`buildTransitive` targets link the archive, direct P/Invokes, and system macOS
frameworks, and remove the replaced `libAvaloniaNative` dynamic publish asset.
They activate only for macOS with `PublishAot=true`. Other RIDs and normal
non-NativeAOT builds are unchanged. Set `EnableStaticAvaloniaNative=false` to
disable only this integration, or `EnableStaticAvalonia=false` to disable both
packages. Do not combine with another package providing these static archives.

## Build And Release

Run **Build and publish LightStudio.AvaloniaStatic.Native** in GitHub Actions.
Set `package_version` to the managed Avalonia version, such as **12.1.4** or
**12.1.5-lightplayer.0**. This value is used for both the NuGet package version
and its exact managed dependency versions. These dependencies are declared in
the NuGet manifest, not restored by the package build, so private or unpublished
managed versions do not block packing. Consumers must have access to the matching
managed packages on their configured NuGet feeds. Set `publish=false` for an
artifact-only build or `publish=true` to publish using `NUGET_API_KEY`.
A tag such as `avalonia-static-native-v12.1.5-lightplayer.0` builds and uploads
without publishing to NuGet.org.

This pipeline builds only Avalonia.Native for the two macOS RIDs; it does not
rebuild or repack SkiaSharp, HarfBuzzSharp, or ANGLE. Changing the package version
does not change the pinned source revision. Update the Native source pin when
the matching managed release changes its native ABI.

Local build on macOS, with Xcode and .NET 10 installed:

```sh
python3 scripts/build-avalonia-static.py osx-x64 --component native --package-version 12.1.5-lightplayer.0
python3 scripts/build-avalonia-static.py osx-arm64 --component native --package-version 12.1.5-lightplayer.0
dotnet pack package/avalonia-static-native/LightStudio.AvaloniaStatic.Native.csproj -c Release -o artifacts/packages -p:PackageVersion=12.1.5-lightplayer.0
```

Collect `artifacts/avalonia-static-native-<rid>` for both macOS RIDs before
packing. Missing archives, provenance, or notices cause packing to fail.
Compilation uses the host CPU count by default; set `JOBS` to override it.
Run a real application publish and rendering smoke test on each target before
distributing a release to consumers.