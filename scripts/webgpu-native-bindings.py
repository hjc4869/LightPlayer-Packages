#!/usr/bin/env python3

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import shlex
import shutil
import struct
import subprocess
import urllib.request
import xml.etree.ElementTree as ET
import zipfile


RIDS = ("linux-x64", "linux-arm64", "android-arm64", "android-x64")


def version(args):
    pin = ET.parse(Path(__file__).resolve().parent.parent / "package/webgpu/Dawn.props")
    value = pin.findtext(f"PropertyGroup/{args.field}")
    if not value:
        raise ValueError(f"Missing Dawn pin: {args.field}")
    print(value)


def prepare_source(args):
    pin = ET.parse(Path(__file__).resolve().parent.parent / "package/webgpu/Dawn.props")
    (args.source / "LIGHTSTUDIO_DAWN_REVISION").write_text(pin.findtext("PropertyGroup/DawnRevision") + "\n")
    cmake = args.source / "src/dawn/CMakeLists.txt"
    source = cmake.read_text()
    marker = 'EXTRA_PARAMETERS "--dawn-dir"\n         "${Dawn_SOURCE_DIR}"'
    replacement = marker + '\n        "--version-file" "${Dawn_SOURCE_DIR}/LIGHTSTUDIO_DAWN_REVISION"'
    if replacement not in source:
        if source.count(marker) != 1:
            raise ValueError("Unrecognized Dawn version generator CMake configuration")
        cmake.write_text(source.replace(marker, replacement))


def export_api(artifact, build, dawn, rid):
    api = artifact / "dawn-api" / rid
    if api.exists():
        shutil.rmtree(api)
    include = api / "include"
    shutil.copytree(dawn / "include", include)
    shutil.copytree(build / "_deps/dawn-build/gen/include", include, dirs_exist_ok=True)
    sources = api / "src"
    sources.mkdir()
    shutil.copyfile(dawn / "LICENSE", api / "LICENSE")
    for name in ("dawn_proc.cpp", "dawn_thread_dispatch_proc.cpp"):
        source = (build / "_deps/dawn-build/gen/src/dawn" / name).read_text()
        if name == "dawn_proc.cpp":
            source = source.replace('#include "src/dawn/common/Compiler.h"', '#define DAWN_NO_SANITIZE(value)')
            source = source.replace('#include "src/utils/assert.h"', '#include <cstdlib>')
            source = source.replace('#include "src/utils/log.h"', '')
            source, count = re.subn(r'(WGPUInstance CreateInstanceThatWarns\([^)]*\)\s*\{).*?\n\}',
                                    r'\1\n    (void)desc;\n    return nullptr;\n}', source, flags=re.DOTALL)
            check = "DAWN_CHECK(std::ranges::equal(procs_->version, dawn::kDawnVersion));"
            if count != 1 or source.count(check) != 1:
                raise ValueError("Unrecognized Dawn proc template; cannot export standalone dispatch")
            source = source.replace(check, "if (!std::ranges::equal(procs_->version, dawn::kDawnVersion)) { std::abort(); }")
        if re.search(r'#include\s+["<]src/', source):
            raise ValueError(f"Private Dawn dependency remains in {name}")
        (sources / name).write_text(source)
    return [package_file(path, f"dawn-api/{rid}/{path.relative_to(api).as_posix()}")
            for path in sorted(api.rglob("*")) if path.is_file()]


def validate_version(value):
    numeric = r"(?:0|[1-9][0-9]*)"
    if not re.fullmatch(rf"{numeric}\.{numeric}\.{numeric}(?:\.[1-9][0-9]*)?(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?", value):
        raise ValueError(f"Expected a normalized NuGet version: {value}")
    core, separator, prerelease = value.partition("-")
    if (any(int(part) > 2147483647 for part in core.split("."))
            or separator and any(part.isdigit() and len(part) > 1 and part.startswith("0") for part in prerelease.split("."))):
        raise ValueError(f"Expected a normalized NuGet version: {value}")


def fetch(args):
    validate_version(args.version)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    package = output / f"LightStudio.WebGPU.{args.version}.nupkg"
    if not package.exists():
        url = ("https://github.com/hjc4869/LightPlayer-Packages/releases/download/"
               f"webgpu-v{args.version}/{package.name}")
        print(f"Downloading {url}", flush=True)
        temporary = package.with_suffix(".partial")
        try:
            with urllib.request.urlopen(url, timeout=120) as response, temporary.open("wb") as stream:
                shutil.copyfileobj(response, stream)
            temporary.replace(package)
        finally:
            temporary.unlink(missing_ok=True)
    with zipfile.ZipFile(package) as archive:
        nuspecs = [name for name in archive.namelist() if name.endswith(".nuspec")]
        if len(nuspecs) != 1:
            raise ValueError(f"Expected one NuGet specification: {package}")
        nuspec = ET.fromstring(archive.read(nuspecs[0]))
        metadata = {element.tag.rsplit("}", 1)[-1]: element.text
                    for element in nuspec.find("{*}metadata")}
        if metadata.get("id") != "LightStudio.WebGPU" or metadata.get("version") != args.version:
            raise ValueError(f"WebGPU NuGet identity mismatch: {package}")
        manifest = json.loads(archive.read("native-bindings/manifest.json"))
        if manifest["package"] != {"id": "LightStudio.WebGPU", "version": args.version}:
            raise ValueError(f"WebGPU manifest version mismatch: {package}")
        profile = manifest["profiles"][args.rid]
        identity = {name: value for name, value in profile.items() if name != "nativeBuildId"}
        root = f"dawn-api/{args.rid}"
        if (profile["id"] != args.rid or profile["abi"]["runtimeIdentifier"] != args.rid
                or fingerprint(identity) != profile["nativeBuildId"] or profile["dawnApi"]["root"] != root):
            raise ValueError(f"WebGPU API identity mismatch: {args.rid}")
        files = profile["dawnApi"]["files"]
        required = {f"{root}/{name}" for name in (
            "include/webgpu/webgpu.h", "include/webgpu/webgpu_cpp.h", "include/dawn/webgpu.h",
            "include/dawn/dawn_proc.h", "include/dawn/dawn_proc_table.h", "include/dawn/dawn_version.h",
            "include/dawn/dawn_thread_dispatch_proc.h", "src/dawn_proc.cpp", "src/dawn_thread_dispatch_proc.cpp", "LICENSE")}
        paths = {entry["path"] for entry in files}
        actual = {entry.filename for entry in archive.infolist()
                  if entry.filename.startswith(f"{root}/") and not entry.is_dir()}
        if not required.issubset(paths) or paths != actual or len(paths) != len(files):
            raise ValueError(f"Incomplete or duplicate Dawn API export: {args.rid}")
        for entry in files:
            logical = PurePosixPath(entry["path"])
            if (logical.is_absolute() or ".." in logical.parts or "\\" in entry["path"]
                    or not entry["path"].startswith(f"{root}/")
                    or archive.getinfo(entry["path"]).external_attr >> 16 & 0o170000 == 0o120000
                    or hashlib.sha256(archive.read(entry["path"])).hexdigest() != entry["sha256"]):
                raise ValueError(f"Unsafe or changed Dawn API file: {entry['path']}")
        api = output / root
        if api.exists():
            shutil.rmtree(api)
        for entry in files:
            destination = output / entry["path"]
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(archive.read(entry["path"]))
    print(f"Validated LightStudio.WebGPU {args.version} ({args.rid}): {output / root}")


def digest(path):
    hasher = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            hasher.update(chunk)
    return hasher.hexdigest()


def fingerprint(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
    temporary.replace(path)


def run(*command, **kwargs):
    return subprocess.check_output(command, text=True, **kwargs).strip()


def package_file(path, logical):
    return {"path": logical, "sha256": digest(path)}


def stage(args):
    artifact = args.artifact.resolve()
    build = args.build.resolve()
    dawn = build / "_deps/dawn-src"
    generated = build / "_deps/dawn-build/gen/include"
    root = f"native-bindings/profiles/{args.rid}"
    profile_root = artifact / root
    include = profile_root / "include"
    if include.exists():
        shutil.rmtree(include)
    for logical, source in (("webgpu/webgpu.h", dawn / "include/webgpu/webgpu.h"),
                            ("dawn/webgpu.h", generated / "dawn/webgpu.h"),
                            ("dawn/dawn_proc_table.h", generated / "dawn/dawn_proc_table.h")):
        destination = include / logical
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)

    commands = json.loads((build / "compile_commands.json").read_text())
    entry = next((entry for entry in commands
                  if "webgpu_dawn_objects.dir/" in entry.get("command", " ".join(entry.get("arguments", [])))), None)
    if entry is None:
        raise ValueError(f"Missing webgpu_dawn compile command: {build}")
    command = entry.get("arguments") or shlex.split(entry["command"])
    compiler = command[0]
    flags = [flag for flag in command[1:]
             if flag.startswith(("--target=", "--sysroot=", "-m", "-fpack-struct", "-fshort-enums",
                                 "-fsigned-char", "-funsigned-char", "-fms-", "-fno-ms-"))
             or flag in ("-pthread", "-fPIC", "-fPIE")]
    flags.append("-DWGPU_SHARED_LIBRARY")
    predefined = dict(re.findall(r"^#define\s+(\w+)\s+(.+)$",
                                run(compiler, *flags, "-dM", "-E", "-x", "c", "-", input=""), re.MULTILINE))
    triple = run(compiler, *flags, "-dumpmachine")
    architecture = "arm64" if "__aarch64__" in predefined else "x64" if "__x86_64__" in predefined else None
    operating_system = "android" if "__ANDROID__" in predefined else "linux"
    if f"{operating_system}-{architecture}" != args.rid:
        raise ValueError(f"Compiler target {triple} does not match {args.rid}")
    run(compiler, *flags, f"-I{include}", "-fsyntax-only", "-x", "c", "-",
        input='#include "webgpu/webgpu.h"\n')
    library = artifact / "libwebgpu_dawn.so"
    with library.open("rb") as stream:
        elf = stream.read(20)
    if elf[:6] != b"\x7fELF\x02\x01" or struct.unpack_from("<H", elf, 18)[0] != (183 if architecture == "arm64" else 62):
        raise ValueError(f"Native library is not little-endian ELF64 for {args.rid}: {library}")
    readelf = Path(compiler).with_name("llvm-readelf")
    dynamic = run(str(readelf) if readelf.is_file() else "readelf", "-dW", str(library))
    soname = re.search(r"\(SONAME\).*\[([^]]+)\]", dynamic)
    if soname is None or soname[1] != library.name:
        raise ValueError(f"Expected SONAME {library.name}: {library}")
    dependencies = re.findall(r"\(NEEDED\).*\[([^]]+)\]", dynamic)
    if any("onnx" in name.lower() for name in dependencies):
        raise ValueError(f"WebGPU must not depend on ONNX: {dependencies}")

    api_files = export_api(artifact, build, dawn, args.rid)
    pin = ET.parse(Path(__file__).resolve().parent.parent / "package/webgpu/Dawn.props")
    upstream = {"tag": pin.findtext("PropertyGroup/DawnTag"),
                "revision": pin.findtext("PropertyGroup/DawnRevision"),
                "source": "https://github.com/google/dawn",
                "archiveSha1": pin.findtext("PropertyGroup/DawnArchiveSha1")}
    configuration_path = profile_root / "configuration/build.json"
    write_json(configuration_path, {"compileCommand": entry, "dawn": upstream})
    headers = [package_file(path, f"{root}/include/{path.relative_to(include).as_posix()}")
               for path in sorted(include.rglob("*.h"))]
    native = package_file(library, f"runtimes/{args.rid}/native/{library.name}")
    native.update({"id": "webgpu_dawn", "role": "shared", "architecture": architecture, "format": "ELF",
                   "runtimeIdentity": soname[1], "dependencies": dependencies, "symbolIndex": "extract-from-asset"})
    profile = {
        "id": args.rid,
        "abi": {"triple": triple, "runtimeIdentifier": args.rid, "operatingSystem": operating_system,
                "architecture": architecture, "endianness": "little", "pointerSize": int(predefined["__SIZEOF_POINTER__"]),
                "longSize": int(predefined["__SIZEOF_LONG__"]), "sizeTSize": int(predefined["__SIZEOF_SIZE_T__"]),
                "charSigned": "__CHAR_UNSIGNED__" not in predefined, "callingConvention": "platform-c"},
        "toolchain": {"compiler": run(compiler, "--version"), "language": "c", "arguments": flags,
                      "predefinedMacros": predefined},
        "sysroot": {"kind": args.sysroot_kind, "version": args.sysroot_version, "redistributed": False},
        "includeRoots": [f"{root}/include"],
        "defines": ["WGPU_SHARED_LIBRARY"],
        "undefines": [],
        "headers": headers,
        "headerTreeSha256": fingerprint(headers),
        "configuration": [package_file(configuration_path, f"{root}/configuration/build.json")],
        "libraries": [native],
        "upstream": {"dawn": upstream},
        "dawnApi": {"root": f"dawn-api/{args.rid}", "files": api_files},
        "features": {"api": "webgpu-c", "linkage": "shared"},
        "link": {"archives": [], "systemLibraries": [], "frameworks": [], "wholeArchive": False,
                 "importToken": soname[1], "backend": "platform-native",
                 "maxPageSize": 16384 if operating_system == "android" else None},
        "licenses": f"licenses/{args.rid}/",
    }
    profile["nativeBuildId"] = fingerprint(profile)
    write_json(profile_root / "profile.json", profile)
    print(f"Recorded {args.rid}: {len(headers)} headers, {native['runtimeIdentity']}")


def manifest(args):
    validate_version(args.version)
    rids = args.rids.split(";")
    if not rids or len(set(rids)) != len(rids) or any(rid not in RIDS for rid in rids):
        raise ValueError(f"Unsupported or duplicate WebGPU RIDs: {args.rids}")
    profiles = {}
    assets = {}
    for rid in rids:
        artifact = (args.artifacts / f"webgpu-{rid}").resolve()
        profile_root = artifact / f"native-bindings/profiles/{rid}"
        profile = json.loads((profile_root / "profile.json").read_text())
        identity = {name: value for name, value in profile.items() if name != "nativeBuildId"}
        if (profile["id"] != rid or profile["abi"]["runtimeIdentifier"] != rid
                or fingerprint(identity) != profile["nativeBuildId"]
                or fingerprint(profile["headers"]) != profile["headerTreeSha256"]):
            raise ValueError(f"Profile identity/hash mismatch: {rid}")
        root = f"native-bindings/profiles/{rid}/"
        native_path = f"runtimes/{rid}/native/libwebgpu_dawn.so"
        if [library["path"] for library in profile["libraries"]] != [native_path]:
            raise ValueError(f"Package/profile native asset mismatch: {rid}")
        api_root = f"dawn-api/{rid}"
        if profile["dawnApi"]["root"] != api_root or not profile["dawnApi"]["files"]:
            raise ValueError(f"Missing or mismatched Dawn API export: {rid}")
        for entry in profile["headers"] + profile["configuration"] + profile["libraries"] + profile["dawnApi"]["files"]:
            logical = PurePosixPath(entry["path"])
            if logical.is_absolute() or ".." in logical.parts or "\\" in entry["path"]:
                raise ValueError(f"Unsafe package path: {logical}")
            if entry["path"].startswith(root):
                source = profile_root / entry["path"][len(root):]
            elif entry["path"] == native_path:
                source = artifact / logical.name
            elif entry["path"].startswith(f"{api_root}/"):
                source = artifact / logical
            else:
                raise ValueError(f"Unexpected profile path: {logical}")
            if source.is_symlink() or not source.resolve().is_relative_to(artifact) or digest(source) != entry["sha256"]:
                raise ValueError(f"Unsafe source or hash mismatch: {source}")
            assets[entry["path"]] = entry["sha256"]
        if not (artifact / "licenses/dawn/LICENSE").is_file():
            raise ValueError(f"Missing Dawn license: {artifact}")
        profiles[rid] = profile
    write_json(args.output, {
        "schemaVersion": 1,
        "status": "prototype",
        "package": {"id": "LightStudio.WebGPU", "version": args.version},
        "profiles": profiles,
        "contentSha256": fingerprint(assets),
        "extractionRequired": ["symbol-index", "recursive-system-header-dependencies", "frontend-abi-conformance"],
    })
    print(f"Validated {len(profiles)} WebGPU profiles and {len(assets)} assets: {args.output}")


def main():
    parser = argparse.ArgumentParser(description="Capture and validate exact-build Dawn WebGPU C header profiles")
    commands = parser.add_subparsers(dest="command", required=True)
    capture = commands.add_parser("stage")
    capture.add_argument("artifact", type=Path)
    capture.add_argument("build", type=Path)
    capture.add_argument("rid", choices=RIDS)
    capture.add_argument("--sysroot-kind", required=True)
    capture.add_argument("--sysroot-version", required=True)
    aggregate = commands.add_parser("manifest")
    aggregate.add_argument("artifacts", type=Path)
    aggregate.add_argument("output", type=Path)
    aggregate.add_argument("--version", required=True)
    aggregate.add_argument("--rids", default=";".join(RIDS))
    pin = commands.add_parser("version")
    pin.add_argument("--field", choices=("DawnTag", "DawnRevision", "DawnArchiveSha1", "DawnPackageVersion"), default="DawnPackageVersion")
    prepare = commands.add_parser("prepare-source")
    prepare.add_argument("source", type=Path)
    download = commands.add_parser("fetch")
    download.add_argument("version")
    download.add_argument("rid", choices=RIDS)
    download.add_argument("output", type=Path)
    validation = commands.add_parser("validate-version")
    validation.add_argument("version")
    args = parser.parse_args()
    {"stage": stage, "manifest": manifest, "version": version, "fetch": fetch,
     "prepare-source": prepare_source, "validate-version": lambda args: validate_version(args.version)}[args.command](args)


if __name__ == "__main__":
    main()