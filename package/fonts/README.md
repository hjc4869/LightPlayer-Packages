# LightStudio.Fonts

Data-only NuGet package containing Noto Sans CJK SC Regular and Bold OpenType fonts
under the SIL Open Font License 1.1. The original font files and license are in
`fonts/`; the package has no managed or native runtime dependency.

## Consume

Reference the package to import the `LightStudioFontsDirectory` MSBuild property:

```xml
<PackageReference Include="LightStudio.Fonts" Version="1.0.0" />
```

For a browser application, copy the fonts and license into the static web assets:

```xml
<Content Include="$(LightStudioFontsDirectory)/*.otf;$(LightStudioFontsDirectory)/OFL.txt"
         Link="wwwroot/fonts/%(Filename)%(Extension)"
         CopyToOutputDirectory="PreserveNewest"
         CopyToPublishDirectory="PreserveNewest" />
```

Load the font files through the application's font manager. Keep `OFL.txt` with
redistributed fonts.

## Build and publish

From the repository root:

```sh
dotnet pack package/fonts/LightStudio.Fonts.csproj -c Debug -o artifacts/packages
```

The [fonts workflow](../../.github/workflows/fonts.yml) builds on `fonts-v*` tags
and manual dispatch. It uploads the NuGet package as a workflow artifact and
attaches it to a GitHub release for tag builds. Manual dispatch accepts
`package_version` and a `publish` flag (default `false`); `publish=true` publishes
a release tagged `fonts-v<package_version>` using the built-in `GITHUB_TOKEN`.
