#!/usr/bin/env python3

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import shlex
import shutil
import subprocess
import xml.etree.ElementTree as ET


REPO = Path(__file__).resolve().parent.parent
LIBRARIES = ("avdevice", "avfilter", "avformat", "avcodec", "swresample", "swscale", "avutil")


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


def definitions(text):
    return dict(re.findall(r"^#define\s+(\w+)\s+(.+)$", text, re.MULTILINE))


def package_file(path, package_path):
    return {"path": package_path, "sha256": digest(path)}


def stage(args):
    artifact = args.artifact.resolve()
    profile_root = artifact / "native-bindings" / "profiles" / args.profile
    include = profile_root / "include"
    for required in ("libavcodec/avcodec.h", "libavformat/avformat.h", "libavutil/avconfig.h", "libavutil/ffversion.h"):
        if not (include / required).is_file():
            raise ValueError(f"Missing installed public header: {include / required}")
    root = f"native-bindings/profiles/{args.profile}"
    headers = [package_file(path, f"{root}/include/{path.relative_to(include).as_posix()}")
               for path in sorted(include.rglob("*.h"))]
    configuration = []
    for name in ("config.h", "config_components.h", "ffbuild/config.mak"):
        destination = profile_root / "configuration" / Path(name).name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(args.build / name, destination)
        configuration.append(package_file(destination, f"{root}/configuration/{destination.name}"))
    for path in sorted((profile_root / "lib" / "pkgconfig").glob("*.pc")):
        configuration.append(package_file(path, f"{root}/lib/pkgconfig/{path.name}"))
    features = definitions((args.build / "config.h").read_text())
    components = definitions((args.build / "config_components.h").read_text())
    build_settings = dict(re.findall(r"^([A-Z][A-Z0-9_]*)=(.*)$",
                                    (args.build / "ffbuild/config.mak").read_text(), re.MULTILINE))
    configured_flags = shlex.split(build_settings.get("CPPFLAGS", "") + " " + build_settings.get("CFLAGS", ""))
    compiler = shlex.split(args.compiler)
    flags = shlex.split(args.flags)
    for flag in configured_flags:
        if flag not in flags and (flag.startswith(("-D", "-U", "-std=", "-fpack-struct", "-fshort-enums",
                                                  "-fsigned-char", "-funsigned-char", "-fms-", "-fno-ms-"))
                                  or flag in ("-pthread", "-fPIC", "-fPIE", "-mms-bitfields")):
            flags.append(flag)
    predefined = definitions(run(*compiler, *flags, "-dM", "-E", "-x", "c", "-", input=""))
    compiler_version = run(*compiler, "--version")
    triple = run(*compiler, *flags, "-dumpmachine")
    sysroot = args.sysroot.resolve()
    sysroot_version = args.sysroot_version
    if not sysroot_version:
        raise ValueError("An explicit sysroot/SDK version is required")
    abi = {
        "triple": triple,
        "runtimeIdentifier": args.rid,
        "operatingSystem": "emscripten" if args.rid == "browser-wasm" else args.rid.split("-")[0],
        "architecture": "wasm32" if args.rid == "browser-wasm" else args.rid.split("-")[-1],
        "endianness": "big" if predefined.get("__BYTE_ORDER__") == "__ORDER_BIG_ENDIAN__" else "little",
        "pointerSize": int(predefined["__SIZEOF_POINTER__"]),
        "longSize": int(predefined["__SIZEOF_LONG__"]),
        "sizeTSize": int(predefined["__SIZEOF_SIZE_T__"]),
        "charSigned": "__CHAR_UNSIGNED__" not in predefined,
        "callingConvention": "platform-c",
    }
    libraries = []
    for path in sorted(artifact.iterdir()):
        shared = path.suffix in (".so", ".dylib", ".dll")
        static = path.suffix in (".a", ".lib")
        if not (shared or static) or (args.linkage == "static" and shared) or (args.linkage == "shared" and static):
            continue
        if shared or args.rid.startswith("ios"):
            directory = f"runtimes/{args.rid}/native"
        elif args.rid == "browser-wasm":
            directory = f"static/{args.profile.replace('wasm-st-', 'wasm-')}"
        else:
            directory = f"static/{args.rid}"
        library = package_file(path, f"{directory}/{path.name}")
        library.update({
            "id": path.stem.removeprefix("lib"),
            "role": "shared" if shared else "implementation-archive",
            "architecture": abi["architecture"],
            "format": "COFF" if args.rid.startswith("win-") else "archive" if static else "Mach-O" if args.rid == "osx-arm64" else "ELF",
            "runtimeIdentity": path.name if shared else None,
            "symbolIndex": "extract-from-asset",
        })
        libraries.append(library)
    if not libraries:
        raise ValueError(f"No native assets for {args.profile}")
    system_libraries = []
    frameworks = []
    if args.rid.startswith("android-"):
        system_libraries = ["c++_static", "c++abi", "z", "android", "mediandk", "log", "dl", "m"]
    elif args.rid.startswith("win-"):
        system_libraries = ["mfuuid", "ole32", "strmiids", "user32", "bcrypt"]
    elif args.rid.endswith("arm64"):
        system_libraries = ["c++", "z"]
        frameworks = ["CoreMedia", "CoreVideo", "VideoToolbox"]
    archives = [library["path"] for library in libraries if library["role"] == "implementation-archive"]
    archives.sort(key=lambda path: next((index for index, name in enumerate(LIBRARIES)
                                        if Path(path).stem in (name, f"lib{name}")), len(LIBRARIES)))
    upstream = {}
    for name in ("ffmpeg", "dav1d", "libjxl", "libxml2", "zlib", "opus", "libjxl/third_party/brotli", "libjxl/third_party/highway", "libjxl/third_party/skcms"):
        upstream[name] = {
            "revision": run("git", "-C", str(REPO / name), "rev-parse", "HEAD"),
            "dirty": bool(run("git", "-C", str(REPO / name), "status", "--porcelain", "--untracked-files=no")),
        }
    profile = {
        "id": args.profile,
        "abi": abi,
        "toolchain": {"compiler": compiler_version, "language": "c", "arguments": flags,
                  "predefinedMacros": predefined, "buildFlags": {name: build_settings.get(name, "")
                                         for name in ("CPPFLAGS", "CFLAGS", "LDFLAGS")}},
        "sysroot": {"kind": args.sysroot_kind, "version": sysroot_version, "buildPath": str(sysroot), "redistributed": False},
        "includeRoots": [f"{root}/include"],
        "defines": [flag[2:] for flag in flags if flag.startswith("-D")],
        "undefines": [flag[2:] for flag in flags if flag.startswith("-U")],
        "headers": headers,
        "headerTreeSha256": fingerprint(headers),
        "configuration": configuration,
        "libraries": libraries,
        "upstream": upstream,
        "features": {name: value for name, value in {**features, **components}.items()
                     if name.startswith(("CONFIG_", "HAVE_")) and value in ("0", "1")},
        "link": {"archives": archives, "systemLibraries": system_libraries, "frameworks": frameworks,
                 "wholeArchive": False, "importToken": "__Internal", "backend": "wasm-native" if args.rid == "browser-wasm" else "platform-native",
                 "localizeArchiveSymbols": args.rid.startswith("android-"),
                 "maxPageSize": 16384 if args.rid.startswith("android-") else None},
        "licenses": "licenses/",
    }
    if args.rid == "browser-wasm":
        profile["wasm"] = {"emscriptenVersion": run(*compiler, "-dumpversion"), "memoryModel": "wasm32",
                           "threads": features.get("HAVE_PTHREADS") == "1", "simd": "simd128",
                           "exceptions": "toolchain-default", "linkFlavor": "emscripten"}
    profile["nativeBuildId"] = fingerprint(profile)
    write_json(profile_root / "profile.json", profile)
    print(f"Recorded {args.profile}: {len(headers)} headers, {len(libraries)} libraries")


def manifest(args):
    profiles = {}
    assets = {}
    for path in sorted(args.artifacts.glob("ffmpeg-*/**/native-bindings/profiles/*/profile.json")):
        profile = json.loads(path.read_text())
        if profile["id"] != path.parent.name:
            raise ValueError(f"Profile directory/identity mismatch: {path}")
        identity = {name: value for name, value in profile.items() if name != "nativeBuildId"}
        if fingerprint(identity) != profile["nativeBuildId"] or fingerprint(profile["headers"]) != profile["headerTreeSha256"]:
            raise ValueError(f"Profile identity/hash mismatch: {path}")
        if profile["id"] in profiles:
            raise ValueError(f"Duplicate profile: {profile['id']}")
        artifact = path.parents[3]
        root = f"native-bindings/profiles/{profile['id']}/"
        for entry in profile["headers"] + profile["configuration"] + profile["libraries"]:
            logical = PurePosixPath(entry["path"])
            if logical.is_absolute() or ".." in logical.parts or "\\" in entry["path"]:
                raise ValueError(f"Unsafe package path: {logical}")
            relative = entry["path"][len(root):] if entry["path"].startswith(root) else None
            source = path.parent / relative if relative is not None else artifact / logical.name
            if source.is_symlink() or not source.resolve().is_relative_to(artifact.resolve()):
                raise ValueError(f"Unsafe source path: {source}")
            if digest(source) != entry["sha256"]:
                raise ValueError(f"Hash mismatch: {source}")
            if entry["path"] in assets and assets[entry["path"]] != entry["sha256"]:
                raise ValueError(f"Conflicting package asset: {logical}")
            assets[entry["path"]] = entry["sha256"]
        profiles[profile["id"]] = profile
    if not profiles:
        raise ValueError("No FFmpeg profiles found; rebuild native artifacts with installed headers first")
    native_paths = set()
    for item in ET.parse(REPO / "package/LightStudio.Ffmpeg.csproj").iter("None"):
        include = item.get("Include", "")
        prefix = "$(FFmpegArtifactsPath)/"
        if include.startswith(prefix) and Path(include).suffix in (".a", ".lib", ".so", ".dll", ".dylib"):
            for source in args.artifacts.glob(include[len(prefix):]):
                native_paths.add(f"{item.attrib['PackagePath'].rstrip('/')}/{source.name}")
    recorded_paths = {library["path"] for profile in profiles.values() for library in profile["libraries"]}
    if native_paths != recorded_paths:
        raise ValueError(f"Package/profile native asset mismatch: unprofiled={sorted(native_paths - recorded_paths)}, "
                         f"unpacked={sorted(recorded_paths - native_paths)}")
    write_json(args.output, {
        "schemaVersion": 1,
        "status": "prototype",
        "package": {"id": "LightStudio.Ffmpeg", "version": args.version},
        "profiles": profiles,
        "contentSha256": fingerprint(assets),
        "extractionRequired": ["symbol-index", "recursive-system-header-dependencies", "frontend-abi-conformance"],
    })
    print(f"Validated {len(profiles)} profiles and {len(assets)} assets: {args.output}")


def main():
    parser = argparse.ArgumentParser(description="Capture and validate exact-build FFmpeg header profiles")
    commands = parser.add_subparsers(dest="command", required=True)
    capture = commands.add_parser("stage")
    capture.add_argument("artifact", type=Path)
    capture.add_argument("build", type=Path)
    capture.add_argument("profile")
    capture.add_argument("rid")
    capture.add_argument("--linkage", choices=("static", "shared", "both"), default="both")
    capture.add_argument("--compiler", required=True)
    capture.add_argument("--flags", default="")
    capture.add_argument("--sysroot", type=Path, required=True)
    capture.add_argument("--sysroot-kind", required=True)
    capture.add_argument("--sysroot-version", required=True)
    aggregate = commands.add_parser("manifest")
    aggregate.add_argument("artifacts", type=Path)
    aggregate.add_argument("output", type=Path)
    aggregate.add_argument("--version", default=ET.parse(REPO / "package/LightStudio.Ffmpeg.csproj").findtext("PropertyGroup/Version"))
    args = parser.parse_args()
    (stage if args.command == "stage" else manifest)(args)


if __name__ == "__main__":
    main()