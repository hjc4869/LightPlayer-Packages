# GeoNames binary format, version 1

All integers are little-endian. Offsets and counts are unsigned 32-bit integers
unless stated otherwise. Sections are contiguous, without alignment padding.
Read fields explicitly rather than casting bytes to native structs. A reader
must reject unsupported versions, invalid section ranges, out-of-range indices,
invalid UTF-8, and unterminated strings.

`0xFFFFFFFF` is the missing-parent sentinel. Entity and city indices are
zero-based, local to a particular database snapshot. GeoNames IDs are the stable
external identifiers; persist them instead of indices.

## Header (64 bytes)

| Byte offset | Type | Meaning |
| --- | --- | --- |
| 0 | 8 bytes | ASCII `LPGEO` followed by three NUL bytes |
| 8 | u32 | Format version: 1 |
| 12 | u32 | Header size: 64 |
| 16 | u32 | Entity count |
| 20 | u32 | City count |
| 24 | u32 | Translation count |
| 28 | u32 | Language count |
| 32 | u32 | Entity section offset, absolute from file start |
| 36 | u32 | City section offset |
| 40 | u32 | Translation section offset |
| 44 | u32 | Language section offset |
| 48 | u32 | String pool offset |
| 52 | u32 | String pool size in bytes |
| 56 | u32 | Reserved: 0 |
| 60 | u32 | Reserved: 0 |

The sections appear in the order listed above. Their sizes follow from record
counts and strides. The string pool ends at EOF. The entire file is smaller
than 4 GiB. Readers should use checked wide arithmetic when validating ranges.

## Entities (24 bytes each)

Entities are sorted by ascending, unique GeoNames ID.

| Byte offset | Type | Meaning |
| --- | --- | --- |
| 0 | u32 | GeoNames ID |
| 4 | u32 | Primary name offset within the string pool |
| 8 | u32 | Code offset within the string pool |
| 12 | u32 | Parent entity index, or `0xFFFFFFFF` |
| 16 | u32 | First translation record index |
| 20 | u16 | Translation record count |
| 22 | u8 | Kind: 0 country, 1 admin1, 2 admin2, 3 populated place |
| 23 | u8 | Reserved: 0 |

Country codes are GeoNames two-letter country codes. Region codes are full
GeoNames composite keys, such as `US.CA` and `US.CA.037`; these administrative
codes are not universally ISO subdivision codes. Populated-place codes are
empty strings.

Countries have no parent. Admin1 points to its country. Admin2 points to its
admin1, or its country if that admin1 is unavailable. Populated places point to
their most specific available region or country. Follow the parent chain and
inspect kinds to retrieve state and country names. A county is not a city:
the populated-place entity supplies the city/town name. Missing levels remain
missing; do not infer a state from a county name.

## Cities and spatial index (12 bytes each)

There is one city record for each populated-place entity.

| Byte offset | Type | Meaning |
| --- | --- | --- |
| 0 | u32 | Populated-place entity index |
| 4 | i32 | Latitude in degrees multiplied by 100,000 |
| 8 | i32 | Longitude in degrees multiplied by 100,000 |

Coordinates use WGS84, quantized to 0.00001 degrees using nearest-even rounding.
Latitude is within [-90, 90] and longitude within [-180, 180]. Latitude or
longitude equal to zero is valid.

The city array encodes a balanced KD-tree without child pointers. For a subtree
in the half-open interval `[lo, hi)`, its root is at `(lo + hi) // 2`, its left
child covers `[lo, root)`, and its right child covers `[root + 1, hi)`.
Start with `[0, city_count)` at depth 0. Empty intervals have no node.

The split axis is `depth % 3`: X, Y, Z. The builder projects the stored integer
coordinates onto a unit sphere using double precision:

```text
lat = latitude / 100000 * pi / 180
lon = longitude / 100000 * pi / 180
X = cos(lat) * cos(lon)
Y = cos(lat) * sin(lon)
Z = sin(lat)
```

Each subtree is partitioned by the split coordinate, then GeoNames ID to break
ties. A reader computes the same projection from each visited city. This avoids
storing a second set of coordinates. Cache projections only if appropriate to
the consuming application's memory and query requirements.

### Nearest-place search

1. Validate that query coordinates are finite and within the ranges above.
   Project the query to the unit sphere without quantizing it.
2. At each visited node, compare the query to that city using squared 3D chord
   distance, `(qx-x)^2 + (qy-y)^2 + (qz-z)^2`.
3. Search the nearer child first, selected by the query's split-axis coordinate.
4. Search the other child if the squared split-axis difference is less than or
   equal to the best squared chord distance. Compare squared values to squared
   values. Equality preserves tie candidates; use the lowest GeoNames ID to
   resolve equal distances.
5. Convert squared chord distance `d2` to great-circle distance:
   `distance_km = 2 * 6371.0088 * asin(min(1, sqrt(d2) / 2))`.
6. Apply the application's distance limit. A result outside that limit is an
   unknown location, not an independently determined country.

The projection handles longitude wraparound and polar locations without special
lat/lon distance corrections. Nearest populated place does not establish which
country, state, or municipality contains the query. Coordinate quantization and
floating-point projection also limit precision.

## Translations (5 bytes each)

| Byte offset | Type | Meaning |
| --- | --- | --- |
| 0 | u8 | Language index |
| 1 | u32 | Name offset within the string pool |

An entity's translation range is sorted by language index and contains at most
one record per language. The 32-bit offset is deliberately unaligned. A missing
translation uses the primary name. Translations equal to that name are omitted.
See [README.md](README.md#localized-names) for source selection and culture mapping.

## Languages (4 bytes each)

Each language record is a u32 string-pool offset for a language tag. Version 1
builds use `en`, `de`, `es`, `fr`, `ja`, `zh-Hans`, `zh-Hant` in that order.
Use the table to resolve indices.

## String pool

The pool contains deduplicated, NUL-terminated UTF-8 strings. Offsets are measured
in bytes from the beginning of this pool, not from the file. Offset 0 contains
the empty string. Every string offset points to a string boundary. Strings are
preserved as supplied by GeoNames, without case folding or Unicode normalization.

## Provenance

`build-info.json` accompanies the binary and identifies each original input by
URL, byte count, and SHA-256. It also records the builder's SHA-256, language
coverage, unresolved administrative codes, and both output checksums.
`geonames.bin.gz` is a deterministic gzip encoding of the entire binary, with
an empty filename and zero modification time.
