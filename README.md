# LightPlayer Packages

This repository builds and publishes `LightStudio.Ffmpeg.browser-wasm`, a NuGet package containing FFmpeg 8.1.2 static libraries for the .NET `browser-wasm` runtime.

## Publish

Push a tag named `ffmpeg-v<package-version>` to build FFmpeg with Emscripten and publish the package to this repository's GitHub Packages feed. For version 8.1.2:

```bash
git tag ffmpeg-v8.1.2
git push origin ffmpeg-v8.1.2
```

The workflow can also be run manually with a NuGet package version from the Actions tab.

## Consume

Add the repository owner's GitHub Packages feed to the consuming project's NuGet configuration:

```xml
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <add key="github-lightstudio" value="https://nuget.pkg.github.com/hjc4869/index.json" />
  </packageSources>
</configuration>
```

Authenticate to the feed with a GitHub token that has `read:packages`, then add the package:

```bash
dotnet add package LightStudio.Ffmpeg.browser-wasm --version 8.1.2
```

The archives are packaged under `runtimes/browser-wasm/native`, which is NuGet's native asset convention for the `browser-wasm` runtime identifier.