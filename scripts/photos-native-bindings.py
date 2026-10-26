#!/usr/bin/env python3

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shlex
import shutil
import subprocess
import xml.etree.ElementTree as ET


REPO = Path(__file__).resolve().parent.parent
PROJECT = REPO / "package/photos/LightStudio.Photos.csproj"
NATIVE_SUFFIXES = (".a", ".lib", ".so", ".dll", ".dylib")
ARCHIVE_ORDER = ("raw", "jxrglue", "jpegxr", "lcms2", "jpeg", "z", "zlib")


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
    return dict(re.findall(r"^#define[ \t]+(\w+)(?:[ \t]+(.*))?$", text, re.MULTILINE))


def package_file(path, logical):
    return {"path": logical, "sha256": digest(path)}


def native_inputs(artifacts):
    inputs = {}
    prefix = "$(PhotosArtifactsPath)/"
    for item in ET.parse(PROJECT).iter("None"):
        for include in item.get("Include", "").split(";"):
            if include.startswith(prefix) and Path(include).suffix in NATIVE_SUFFIXES:
                source = artifacts / include[len(prefix):]
                logical = f"{item.attrib['PackagePath'].rstrip('/')}/{source.name}"
                if logical in inputs:
                    raise ValueError(f"Duplicate native package path: {logical}")
                inputs[logical] = source
    return inputs


def sdk_identity(target, compiler, flags):
    if target.startswith("android-"):
        ndk = next((os.environ[name] for name in ("ANDROID_NDK_HOME", "ANDROID_NDK_LATEST_HOME", "ANDROID_NDK_ROOT")
                    if os.environ.get(name)), "/usr/lib/android-ndk")
        properties = (Path(ndk) / "source.properties").read_text()
        version = re.search(r"^Pkg.Revision\s*=\s*(.+)$", properties, re.MULTILINE)[1]
        return {"kind": "android-ndk", "version": version,
                "apiLevel": os.environ.get("ANDROID_API_LEVEL", "21"), "redistributed": False}
    if target.startswith("browser-wasm"):
        return {"kind": "emscripten", "version": run(*compiler, "-dumpversion"), "redistributed": False}
    if target.startswith(("osx-", "ios-", "iossimulator-")):
        sdk = "macosx" if target.startswith("osx-") else "iphonesimulator" if target.startswith("iossimulator-") else "iphoneos"
        return {"kind": sdk, "version": run("xcrun", "--sdk", sdk, "--show-sdk-version"),
                "deploymentTarget": os.environ.get("MACOSX_DEPLOYMENT_TARGET" if sdk == "macosx" else "IPHONEOS_DEPLOYMENT_TARGET"),
                "redistributed": False}
    if target.startswith("win-") and "msvc" in run(*compiler, *flags, "-dumpmachine"):
        version = os.environ.get("WindowsSDKVersion", "").rstrip("/\\")
        if not version:
            raise ValueError("WindowsSDKVersion is required for MSVC header profiles")
        return {"kind": "windows-sdk", "version": version,
                "msvcVersion": os.environ.get("VCToolsVersion"), "redistributed": False}
    header = "_mingw.h" if target.startswith("win-") else "features.h"
    macros = definitions(run(*compiler, *flags, "-dM", "-E", "-x", "c", "-", input=f"#include <{header}>\n"))
    names = ("__MINGW64_VERSION_MAJOR", "__MINGW64_VERSION_MINOR") if target.startswith("win-") else ("__GLIBC__", "__GLIBC_MINOR__")
    return {"kind": "mingw-w64" if target.startswith("win-") else "glibc",
            "version": ".".join(macros[name] for name in names), "redistributed": False}


def stage(args):
    artifact = args.artifact.resolve()
    compiler = shlex.split(args.compiler)
    flags = shlex.split(args.flags)
    predefined = definitions(run(*compiler, *flags, "-dM", "-E", "-x", "c", "-", input=""))
    rid = "browser-wasm" if args.target.startswith("browser-wasm") else args.target
    architecture = "wasm32" if rid == "browser-wasm" else rid.split("-")[-1]
    expected_macro = {"arm64": "__aarch64__", "x64": "__x86_64__", "wasm32": "__wasm32__"}[architecture]
    os_macro = {"android": "__ANDROID__", "win": "_WIN32", "linux": "__linux__", "osx": "__APPLE__",
                "ios": "__APPLE__", "iossimulator": "__APPLE__", "browser": "__EMSCRIPTEN__"}[rid.split("-")[0]]
    if expected_macro not in predefined or os_macro not in predefined:
        raise ValueError(f"Compiler target does not match {args.target}")
    root = f"native-bindings/profiles/{args.profile}"
    profile_root = artifact / root
    include = profile_root / "include"
    if include.exists():
        shutil.rmtree(include)
    shutil.copytree(args.prefix / "include", include)
    for required in ("libraw/libraw.h", "libraw/libraw_types.h", "lcms2.h", "jpeglib.h", "jconfig.h", "zlib.h",
                     "jxrlib/JXRGlue.h", "jxrlib/compat.h"):
        if not (include / required).is_file():
            raise ValueError(f"Missing installed public header: {required}")
    shutil.copyfile(args.build / "jpeg-namespace.h", include / "photos-jpeg-namespace.h")
    headers = [package_file(path, f"{root}/include/{path.relative_to(include).as_posix()}")
               for path in sorted(include.rglob("*.h"))]
    configuration = []
    for pattern in ("*-build/config.h", "*-build/CMakeCache.txt", "*-build/Makefile"):
        for source in sorted(args.build.glob(pattern)):
            relative = f"configuration/{source.parent.name}/{source.name}"
            destination = profile_root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, destination)
            configuration.append(package_file(destination, f"{root}/{relative}"))
    libraries = []
    for source in sorted(artifact.iterdir()):
        if source.suffix not in NATIVE_SUFFIXES:
            continue
        shared = source.suffix in (".so", ".dll", ".dylib")
        directory = f"runtimes/{rid}/native" if shared or rid.startswith("ios") else (
            f"static/{args.profile.replace('browser-', '')}" if rid == "browser-wasm" else f"static/{rid}")
        name = source.stem.removeprefix("lib")
        library = package_file(source, f"{directory}/{source.name}")
        library.update({"id": name, "role": "shared" if shared else "implementation-archive", "architecture": architecture,
                        "format": "COFF" if rid.startswith("win-") else "archive" if not shared else "Mach-O" if rid.startswith("osx-") else "ELF",
                        "runtimeIdentity": source.name if shared else None, "symbolIndex": "extract-from-asset"})
        libraries.append(library)
    if not libraries:
        raise ValueError(f"No native assets for {args.profile}")
    windows = rid.startswith("win-")
    shared_windows = windows and args.linkage == "shared"
    header_contexts = {
        "libraw": {"entryHeaders": ["libraw/libraw.h"], "defines": ["LIBRAW_WIN32_DLLDEFS"] if shared_windows else ["LIBRAW_NODLL"] if windows else [],
                   "undefines": [], "forcedIncludes": []},
        "lcms2": {"entryHeaders": ["lcms2.h"], "defines": ["CMS_DLL"] if shared_windows else [], "undefines": [], "forcedIncludes": []},
        "jxrlib": {"entryHeaders": ["jxrlib/JXRGlue.h"], "includeRoots": [f"{root}/include/jxrlib"], "defines": ["__ANSI__", "DISABLE_PERF_MEASUREMENT"],
                   "undefines": ["WIN32"], "forcedIncludes": [f"{root}/include/jxrlib/compat.h"]},
        "jpeg": {"entryHeaders": ["stddef.h", "stdio.h", "jpeglib.h"], "defines": [], "undefines": [],
                 "forcedIncludes": [f"{root}/include/photos-jpeg-namespace.h"]},
    }
    archives = [library["path"] for library in libraries if library["role"] == "implementation-archive"]
    archives.sort(key=lambda path: ARCHIVE_ORDER.index(Path(path).stem.removeprefix("lib")))
    upstream = {name: {"revision": run("git", "-C", str(REPO / name), "rev-parse", "HEAD"),
                       "dirty": bool(run("git", "-C", str(REPO / name), "status", "--porcelain", "--untracked-files=no"))}
                for name in ("libraw", "lcms2", "libjpeg-turbo", "zlib", "jxrlib")}
    profile = {
        "id": args.profile,
        "abi": {"triple": run(*compiler, *flags, "-dumpmachine"), "runtimeIdentifier": rid,
                "operatingSystem": "emscripten" if rid == "browser-wasm" else rid.split("-")[0], "architecture": architecture,
                "endianness": "big" if predefined.get("__BYTE_ORDER__") == "__ORDER_BIG_ENDIAN__" else "little",
                "pointerSize": int(predefined["__SIZEOF_POINTER__"]), "longSize": int(predefined["__SIZEOF_LONG__"]),
                "sizeTSize": int(predefined["__SIZEOF_SIZE_T__"]), "charSigned": "__CHAR_UNSIGNED__" not in predefined, "callingConvention": "platform-c"},
        "toolchain": {"compiler": run(*compiler, "--version"), "language": "c", "arguments": flags,
                      "predefinedMacros": predefined, "buildFlags": args.build_flags},
        "sysroot": sdk_identity(args.target, compiler, flags),
        "includeRoots": [f"{root}/include"],
        "defines": [flag[2:] for flag in flags if flag.startswith("-D")],
        "undefines": [flag[2:] for flag in flags if flag.startswith("-U")],
        "headerContexts": header_contexts,
        "headers": headers, "headerTreeSha256": fingerprint(headers), "configuration": configuration,
        "libraries": libraries, "upstream": upstream,
        "features": {"linkage": args.linkage, "jpeg": True, "zlib": True, "lcms2": True, "jpegXR": True,
                     "jpegEmbeddedInLibRaw": rid == "browser-wasm", "jpegSymbolPrefix": "lightstudio_photos_"},
        "link": {"archives": archives, "systemLibraries": ["ws2_32"] if windows else ["c++", "m"] if rid.startswith(("osx-", "ios")) else
                 ["c++_static", "c++abi", "dl", "m"] if rid.startswith("android-") else ["stdc++", "m", "pthread"] if rid.startswith("linux-") else [],
                 "frameworks": [], "wholeArchive": False, "importToken": "__Internal", "backend": "wasm-native" if rid == "browser-wasm" else "platform-native",
                 "maxPageSize": 16384 if rid.startswith("android-") else None},
        "licenses": "licenses/",
    }
    if rid == "browser-wasm":
        profile["wasm"] = {"emscriptenVersion": run(*compiler, "-dumpversion"), "memoryModel": "wasm32", "threads": "-pthread" in flags,
                           "simd": "simd128", "exceptions": "wasm-native", "linkFlavor": "emscripten"}
    profile["nativeBuildId"] = fingerprint(profile)
    write_json(profile_root / "profile.json", profile)
    print(f"Recorded {args.profile}: {len(headers)} headers, {len(libraries)} libraries")


def manifest(args):
    profiles = {}
    assets = {}
    expected = native_inputs(args.artifacts)
    recorded = set()
    for path in sorted(args.artifacts.glob("photos-*/**/native-bindings/profiles/*/profile.json")):
        profile = json.loads(path.read_text())
        identity = {name: value for name, value in profile.items() if name != "nativeBuildId"}
        if (profile["id"] != path.parent.name or profile["id"] in profiles
                or fingerprint(identity) != profile["nativeBuildId"] or fingerprint(profile["headers"]) != profile["headerTreeSha256"]):
            raise ValueError(f"Profile identity/hash mismatch: {path}")
        artifact = path.parents[3]
        root = f"native-bindings/profiles/{profile['id']}/"
        for entry in profile["headers"] + profile["configuration"] + profile["libraries"]:
            logical = PurePosixPath(entry["path"])
            if logical.is_absolute() or ".." in logical.parts or "\\" in entry["path"]:
                raise ValueError(f"Unsafe package path: {logical}")
            if entry["path"].startswith(root):
                source = path.parent / entry["path"][len(root):]
            elif entry["path"] in expected:
                source = expected[entry["path"]]
                recorded.add(entry["path"])
            else:
                raise ValueError(f"Unexpected native asset: {logical}")
            if source.is_symlink() or not source.resolve().is_relative_to(artifact.resolve()) or digest(source) != entry["sha256"]:
                raise ValueError(f"Unsafe source or hash mismatch: {source}")
            if entry["path"] in assets:
                raise ValueError(f"Duplicate package asset: {logical}")
            assets[entry["path"]] = entry["sha256"]
        profiles[profile["id"]] = profile
    if not profiles or recorded != set(expected):
        raise ValueError(f"Missing Photos header profiles/native assets; rebuild all targets: {sorted(set(expected) - recorded)}")
    write_json(args.output, {"schemaVersion": 1, "status": "prototype", "package": {"id": "LightStudio.Photos", "version": args.version},
                             "profiles": profiles, "contentSha256": fingerprint(assets),
                             "extractionRequired": ["symbol-index", "recursive-system-header-dependencies", "frontend-abi-conformance"]})
    print(f"Validated {len(profiles)} Photos profiles and {len(assets)} assets: {args.output}")


def main():
    parser = argparse.ArgumentParser(description="Capture and validate exact-build Photos header profiles")
    commands = parser.add_subparsers(dest="command", required=True)
    capture = commands.add_parser("stage")
    capture.add_argument("artifact", type=Path)
    capture.add_argument("build", type=Path)
    capture.add_argument("prefix", type=Path)
    capture.add_argument("profile")
    capture.add_argument("target")
    capture.add_argument("--compiler", required=True)
    capture.add_argument("--flags", default="")
    capture.add_argument("--build-flags", default="")
    capture.add_argument("--linkage", choices=("static", "shared", "both"), required=True)
    aggregate = commands.add_parser("manifest")
    aggregate.add_argument("artifacts", type=Path)
    aggregate.add_argument("output", type=Path)
    aggregate.add_argument("--version", required=True)
    args = parser.parse_args()
    (stage if args.command == "stage" else manifest)(args)


if __name__ == "__main__":
    main()