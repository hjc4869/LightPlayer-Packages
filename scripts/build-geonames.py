#!/usr/bin/env python3
import argparse
from collections import Counter
from dataclasses import dataclass
from decimal import Decimal, ROUND_HALF_EVEN
import gzip
import hashlib
import io
import json
import math
from pathlib import Path
import shutil
import struct
import sys
import urllib.request
import zipfile


ROOT = Path(__file__).resolve().parents[1]
SOURCE_URL = "https://download.geonames.org/export/dump/"
SOURCE_FILES = (
    "cities1000.zip", "countryInfo.txt", "admin1CodesASCII.txt",
    "admin2Codes.txt", "alternateNamesV2.zip",
)
LANGUAGES = ("en", "de", "es", "fr", "ja", "zh-Hans", "zh-Hant")
LANGUAGE_SOURCES = {
    "en": ((0, 0),), "en-gb": ((0, 1),), "en-us": ((0, 2),),
    "de": ((1, 0),), "de-de": ((1, 1),),
    "es": ((2, 0),), "es-es": ((2, 1),),
    "fr": ((3, 0),), "fr-fr": ((3, 1),),
    "ja": ((4, 0),), "ja-jp": ((4, 1),),
    "zh-hans": ((5, 0),), "zh-cn": ((5, 0),), "zh-sg": ((5, 1),),
    "zh-hant": ((6, 0),), "zh-tw": ((6, 0),),
    "zh-hk": ((6, 1),), "zh-mo": ((6, 1),),
    "zh": ((5, 2), (6, 2)),
}
HEADER = struct.Struct("<8s14I")
ENTITY = struct.Struct("<IIIIIHBB")
CITY = struct.Struct("<Iii")
TRANSLATION = struct.Struct("<BI")
UINT32_MAX = 0xFFFFFFFF


@dataclass(frozen=True, slots=True)
class Entity:
    geoname_id: int
    name: str
    code: str
    parent_id: int | None
    kind: int


@dataclass(frozen=True, slots=True)
class City:
    geoname_id: int
    latitude: int
    longitude: int
    point: tuple[float, float, float]


class StringPool:
    def __init__(self):
        self.data = bytearray(b"\0")
        self.offsets = {"": 0}

    def intern(self, value):
        if "\0" in value:
            raise ValueError(f"Embedded NUL in GeoNames string: {value!r}")
        if value not in self.offsets:
            self.offsets[value] = len(self.data)
            self.data.extend(value.encode("utf-8") + b"\0")
        return self.offsets[value]


def sha256(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def download_sources(directory):
    directory.mkdir(parents=True, exist_ok=True)
    for name in SOURCE_FILES:
        destination = directory / name
        temporary = destination.with_suffix(destination.suffix + ".download")
        print(f"Downloading {SOURCE_URL}{name}", flush=True)
        request = urllib.request.Request(SOURCE_URL + name, headers={"User-Agent": "LightStudio.GeoNames/1"})
        try:
            with urllib.request.urlopen(request, timeout=120) as response, temporary.open("wb") as output:
                shutil.copyfileobj(response, output)
                expected = response.headers.get("Content-Length")
            if temporary.stat().st_size == 0 or (expected and temporary.stat().st_size != int(expected)):
                raise ValueError(f"Incomplete download: {name}")
            temporary.replace(destination)
        finally:
            temporary.unlink(missing_ok=True)


def rows(stream, name, minimum_fields):
    for line_number, line in enumerate(stream, 1):
        if line.startswith("#") or not line.strip():
            continue
        fields = line.rstrip("\r\n").split("\t")
        if len(fields) < minimum_fields:
            raise ValueError(f"{name}:{line_number}: expected at least {minimum_fields} fields, got {len(fields)}")
        yield fields


def text_rows(path, minimum_fields):
    with path.open(encoding="utf-8") as stream:
        yield from rows(stream, path.name, minimum_fields)


def zip_rows(path, member, minimum_fields):
    with zipfile.ZipFile(path) as archive, archive.open(member) as binary:
        with io.TextIOWrapper(binary, encoding="utf-8") as stream:
            yield from rows(stream, f"{path.name}/{member}", minimum_fields)


def coordinate(value, limit):
    number = Decimal(value)
    if not number.is_finite() or not -limit <= number <= limit:
        raise ValueError(f"Invalid coordinate: {value}")
    return int((number * 100_000).to_integral_value(rounding=ROUND_HALF_EVEN))


def add_entity(entities, entity):
    if not 0 < entity.geoname_id < UINT32_MAX or not entity.name:
        raise ValueError(f"Invalid GeoNames entity: {entity}")
    previous = entities.get(entity.geoname_id)
    if previous is not None and previous != entity:
        raise ValueError(f"Conflicting GeoNames ID: {previous} and {entity}")
    entities[entity.geoname_id] = entity


def load_places(directory):
    entities = {}
    countries = {}
    for fields in text_rows(directory / "countryInfo.txt", 17):
        entity = Entity(int(fields[16]), fields[4], fields[0], None, 0)
        add_entity(entities, entity)
        if entity.code in countries:
            raise ValueError(f"Duplicate country code: {entity.code}")
        countries[entity.code] = entity

    regions = {}
    for name, kind in (("admin1CodesASCII.txt", 1), ("admin2Codes.txt", 2)):
        regions[kind] = {}
        for fields in text_rows(directory / name, 4):
            code = fields[0]
            country = countries.get(code.split(".")[0])
            if country is None:
                raise ValueError(f"{name}: unknown country for {code}")
            parent = regions[1].get(code.rsplit(".", 1)[0], country) if kind == 2 else country
            entity = Entity(int(fields[3]), fields[1], code, parent.geoname_id, kind)
            if code in regions[kind]:
                raise ValueError(f"{name}: duplicate administrative code {code}")
            regions[kind][code] = entity

    cities = []
    missing = {1: set(), 2: set()}
    city_ids = set()
    for fields in zip_rows(directory / "cities1000.zip", "cities1000.txt", 19):
        geoname_id = int(fields[0])
        if geoname_id in city_ids or fields[6] != "P":
            raise ValueError(f"Invalid or duplicate city: {fields[0:2]}")
        city_ids.add(geoname_id)
        country = countries.get(fields[8])
        if country is None:
            raise ValueError(f"Unknown country {fields[8]!r} for city {geoname_id}")
        parent = country
        for kind, parts in ((1, fields[8:9] + fields[10:11]), (2, fields[8:9] + fields[10:12])):
            if not all(parts):
                continue
            code = ".".join(parts)
            region = regions[kind].get(code)
            if region is None:
                missing[kind].add(code)
                continue
            if kind == 2 and region.parent_id not in entities:
                admin1 = regions[1].get(code.rsplit(".", 1)[0])
                if admin1 is not None:
                    add_entity(entities, admin1)
            add_entity(entities, region)
            parent = region
        add_entity(entities, Entity(geoname_id, fields[1], "", parent.geoname_id, 3))
        latitude = coordinate(fields[4], 90)
        longitude = coordinate(fields[5], 180)
        lat, lon = math.radians(latitude / 100_000), math.radians(longitude / 100_000)
        point = (math.cos(lat) * math.cos(lon), math.cos(lat) * math.sin(lon), math.sin(lat))
        cities.append(City(geoname_id, latitude, longitude, point))
    if not cities:
        raise ValueError("cities1000 contains no populated places")
    for kind, codes in missing.items():
        if codes:
            print(f"Warning: {len(codes)} admin{kind} codes have no GeoNames name; retaining available ancestors.",
                  file=sys.stderr)
    return entities, cities, {f"admin{kind}": sorted(codes) for kind, codes in missing.items()}


def load_translations(directory, entity_ids):
    translations = {}
    for fields in zip_rows(directory / "alternateNamesV2.zip", "alternateNamesV2.txt", 10):
        targets = LANGUAGE_SOURCES.get(fields[2].lower())
        if targets is None:
            continue
        geoname_id = int(fields[1])
        if geoname_id not in entity_ids or fields[6] == "1" or fields[7] == "1" or fields[9]:
            continue
        if not fields[3]:
            raise ValueError(f"Empty alternate name: {fields[0]}")
        choices = translations.setdefault(geoname_id, {})
        for language, specificity in targets:
            rank = (specificity, fields[4] != "1", fields[5] == "1", int(fields[0]))
            if language not in choices or rank < choices[language][0]:
                choices[language] = (rank, fields[3])
    return translations


def order_cities(cities, depth=0):
    if not cities:
        return
    axis = depth % 3
    ordered = sorted(cities, key=lambda city: (city.point[axis], city.geoname_id))
    middle = len(ordered) // 2
    yield from order_cities(ordered[:middle], depth + 1)
    yield ordered[middle]
    yield from order_cities(ordered[middle + 1:], depth + 1)


def build_database(entities, cities, translations):
    pool = StringPool()
    entity_data = bytearray()
    translation_data = bytearray()
    counts = Counter()
    ordered = sorted(entities.values(), key=lambda entity: entity.geoname_id)
    indices = {entity.geoname_id: index for index, entity in enumerate(ordered)}
    for entity in ordered:
        start = len(translation_data) // TRANSLATION.size
        for language, (_, name) in sorted(translations.get(entity.geoname_id, {}).items()):
            counts[LANGUAGES[language]] += 1
            if name != entity.name:
                translation_data.extend(TRANSLATION.pack(language, pool.intern(name)))
        count = len(translation_data) // TRANSLATION.size - start
        parent = UINT32_MAX if entity.parent_id is None else indices[entity.parent_id]
        entity_data.extend(ENTITY.pack(entity.geoname_id, pool.intern(entity.name), pool.intern(entity.code),
                                       parent, start, count, entity.kind, 0))
    city_data = b"".join(CITY.pack(indices[city.geoname_id], city.latitude, city.longitude)
                         for city in order_cities(cities))
    language_data = b"".join(struct.pack("<I", pool.intern(language)) for language in LANGUAGES)
    entity_offset = HEADER.size
    city_offset = entity_offset + len(entity_data)
    translation_offset = city_offset + len(city_data)
    language_offset = translation_offset + len(translation_data)
    string_offset = language_offset + len(language_data)
    if string_offset + len(pool.data) > UINT32_MAX:
        raise ValueError("GeoNames database exceeds the format's 4 GiB limit")
    header = HEADER.pack(b"LPGEO\0\0\0", 1, HEADER.size, len(entities), len(cities),
                         len(translation_data) // TRANSLATION.size, len(LANGUAGES),
                         entity_offset, city_offset, translation_offset, language_offset,
                         string_offset, len(pool.data), 0, 0)
    data = header + entity_data + city_data + translation_data + language_data + pool.data
    return data, {
        "entities": len(entities), "cities": len(cities),
        "entities_by_kind": dict(sorted(Counter(entity.kind for entity in ordered).items())),
        "translations": len(translation_data) // TRANSLATION.size,
        "localized_entities": {language: counts[language] for language in LANGUAGES},
        "unique_strings": len(pool.offsets),
    }


def main():
    parser = argparse.ArgumentParser(description="Build the compact, localized LightStudio.GeoNames database.")
    parser.add_argument("--download", action="store_true", help="Refresh all input files from GeoNames before building.")
    parser.add_argument("--source-dir", type=Path, default=ROOT / "artifacts/sources/geonames",
                        help="Directory containing the five original GeoNames files; retained for offline rebuilds.")
    parser.add_argument("--output-dir", type=Path, default=ROOT / "artifacts/geonames",
                        help="Directory for the binary, gzip copy, provenance manifest, and attribution notice.")
    args = parser.parse_args()
    if args.source_dir.resolve() == args.output_dir.resolve():
        parser.error("--source-dir and --output-dir must be different directories")
    if args.download:
        download_sources(args.source_dir)
    source_info = []
    for name in SOURCE_FILES:
        path = args.source_dir / name
        source_info.append({"file": name, "url": SOURCE_URL + name, "bytes": path.stat().st_size, "sha256": sha256(path)})
    print("Loading countries, administrative regions, and populated places.", flush=True)
    entities, cities, missing = load_places(args.source_dir)
    print(f"Selecting localized names for {len(entities)} entities.", flush=True)
    translations = load_translations(args.source_dir, entities.keys())
    print("Building shared strings and balanced spherical KD-tree.", flush=True)
    data, counts = build_database(entities, cities, translations)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    destination = args.output_dir / "geonames.bin"
    destination.write_bytes(data)
    compressed = args.output_dir / "geonames.bin.gz"
    with compressed.open("wb") as output:
        with gzip.GzipFile(filename="", mode="wb", fileobj=output, compresslevel=9, mtime=0) as archive:
            archive.write(data)
    shutil.copyfile(ROOT / "package/geonames/THIRD-PARTY-NOTICES.txt",
                    args.output_dir / "THIRD-PARTY-NOTICES.txt")
    manifest = {
        "format_version": 1,
        "builder_sha256": sha256(Path(__file__).resolve()),
        "attribution": "GeoNames, https://www.geonames.org/",
        "license": "CC-BY-4.0",
        "license_url": "https://creativecommons.org/licenses/by/4.0/",
        "languages": LANGUAGES,
        "sources": source_info,
        "counts": counts,
        "missing_admin_codes": missing,
        "outputs": [{"file": path.name, "bytes": path.stat().st_size, "sha256": sha256(path)}
                    for path in (destination, compressed)],
    }
    (args.output_dir / "build-info.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=True) + "\n",
                                                   encoding="utf-8")
    print(f"Built {counts['cities']} places: {len(data):,} bytes; gzip: {compressed.stat().st_size:,} bytes.", flush=True)


if __name__ == "__main__":
    main()
