# LightStudio.GeoNames

A data-only NuGet package for offline nearest-place lookup. It contains populated
places from GeoNames `cities1000`, country names, available first- and second-level
administrative regions, and selected localized names. `cities1000` includes places
with population over 1,000 and administrative seats down to PPLA3.

The database contains the populated place's own name. Administrative level 1
represents a state or region; level 2 can represent a county, district, or council
area. Administrative meanings vary between countries.

## Package contents

- `data/geonames.bin.gz`: gzip-compressed binary database.
- `data/build-info.json`: source URLs, input and output SHA-256 checksums,
  builder checksum, record counts, and missing administrative codes.
- `build/LightStudio.GeoNames.props`: MSBuild paths to the packaged data.
- `THIRD-PARTY-NOTICES.txt`: redistribution attribution.
- `FORMAT.md`: binary layout and lookup instructions.

The package adds no files to build output. A project referencing it receives the
`LightStudioGeoNamesDatabase` and `LightStudioGeoNamesBuildInfo` properties,
which hold absolute paths to the packaged files. For example, embed the
compressed database in an assembly:

```xml
<ItemGroup>
  <PackageReference Include="LightStudio.GeoNames" PrivateAssets="all" />
  <EmbeddedResource Include="$(LightStudioGeoNamesDatabase)" LogicalName="geonames.bin.gz" />
</ItemGroup>
```

Decompress the gzip stream before random access. The package supplies data, not
executable lookup code. The standalone build artifact also includes the
uncompressed `geonames.bin`.

## Offline lookup

The database uses integer WGS84 coordinates, a shared UTF-8 string pool, stable
GeoNames IDs, sparse localized names, and a balanced 3D unit-sphere KD-tree.
Entity records are ordered by GeoNames ID, allowing binary search when resolving
a saved ID after a database update.

Readers can use memory mapping on platforms that support it or an in-memory byte
buffer on other platforms. The format uses fixed-width integers and explicit
little-endian reads, without serialization or reflection requirements.

Nearest-place lookup is an approximation, not an administrative boundary check.
A nearby place may be across a state or country border. Readers should choose a
distance limit appropriate to the feature; a 50 km starting point is reasonable
for photo labels. If no place satisfies the limit, return an unknown location:
this dataset cannot determine the containing country independently of a place.
Zero latitude or longitude is valid. See [FORMAT.md](FORMAT.md) for search details.

## Localized names

Name slots cover English (`en`), German (`de`), Spanish (`es`), French (`fr`),
Japanese (`ja`), Simplified Chinese (`zh-Hans`), and Traditional Chinese
(`zh-Hant`). Consumers map regional UI cultures such as `en-GB` or `de-DE` to the
matching language; map `zh-CN`/`zh-SG` to `zh-Hans` and
`zh-TW`/`zh-HK`/`zh-MO` to `zh-Hant`.

The builder selects names from `alternateNamesV2` for retained entities.
It excludes colloquial and historic names and names with an end date. Source
language specificity takes priority, followed by preferred status, non-short
status, and the lowest alternate-name ID. The source language aliases are
defined in `LANGUAGE_SOURCES` in the builder.

For Chinese, script-specific tags and `zh-CN`/`zh-TW` have first priority;
`zh-SG`/`zh-HK`/`zh-MO` follow. Generic `zh` is the final fallback for either
slot and may contain either script. The builder preserves the source spelling.
No script conversion is performed. Other languages prefer the base language to
the listed regional variants.

If there is no selected translation, use the entity's primary name. A primary
name is not guaranteed to be English. Translations equal to the primary name
are omitted from the binary. Localization coverage depends on GeoNames;
`localized_entities` in the manifest counts selected names, including those
identical to the primary name.

## Build

Python 3.12 or newer and the .NET 8 SDK or newer are required. The Python builder
uses only the standard library.

From the repository root:

```sh
python3 scripts/build-geonames.py --download
dotnet pack package/geonames/LightStudio.GeoNames.csproj -c Debug \
  -o artifacts/packages -p:PackageVersion=1.0.0
```

The builder downloads these original files directly from
<https://download.geonames.org/export/dump/>:

- `cities1000.zip`
- `countryInfo.txt`
- `admin1CodesASCII.txt`
- `admin2Codes.txt`
- `alternateNamesV2.zip`

Inputs are retained under `artifacts/sources/geonames/`. Omit `--download` to
rebuild offline from that snapshot. `--source-dir` and `--output-dir` select
different input/output directories. `GeoNamesArtifactsPath` overrides the
database directory when packing.

The upstream files are mutable snapshots, not versioned releases, and are fetched
separately. The manifest records the exact bytes used, rather than promising an
atomic upstream snapshot. Keep those inputs for reproducibility. For identical
inputs and the same Python environment, binary output, gzip output, and manifest
are deterministic. No build timestamp is embedded.

Only regions referenced by retained places and their available ancestors are
included; countries are retained from `countryInfo`. Unknown administrative codes
produce warnings and are listed in the manifest. The hierarchy skips missing
regions and retains the available ancestors.

## GitHub Actions

[The GeoNames workflow](https://github.com/hjc4869/LightPlayer-Packages/blob/master/.github/workflows/geonames.yml)
runs on a `geonames-v*` tag or manual dispatch. It downloads current inputs, builds
the database, and uploads three artifacts:

- `geonames-database`: binary database, gzip database, provenance manifest, and
  attribution notice.
- `geonames-source-snapshot`: original inputs for offline rebuilds.
- `LightStudio.GeoNames-nuget`: NuGet package with the gzip database and attribution.

Manual dispatch accepts `package_version` and a `publish` flag, which defaults
to false. With `publish=true`, the workflow attaches the package to a GitHub
release tagged `geonames-v<package_version>` using the built-in `GITHUB_TOKEN`.
Pushing a tag such as `geonames-v1.0.0` also builds and publishes a release for
that tag. Use a new package version when publishing updated data. The binary
format version is independent of the package version.

## Attribution

Data is derived from [GeoNames](https://www.geonames.org/) under
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Redistribution requires
attribution, a license link, and identification of changes. Retain
`THIRD-PARTY-NOTICES.txt` and expose appropriate attribution in the consuming
application. GeoNames supplies the data without warranties of accuracy,
timeliness, or completeness.
