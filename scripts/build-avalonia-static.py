#!/usr/bin/env python3
import argparse
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / "scripts/avalonia-static"
SOURCES = json.loads((CONFIG / "sources.json").read_text())
RIDS = [f"{system}-{arch}" for system in ("android", "osx", "linux", "win") for arch in ("x64", "arm64")]


def run(*command, cwd=None, capture=False, input_text=None):
    command = [str(part) for part in command]
    if os.name == "nt" and Path(shutil.which(command[0]) or command[0]).suffix.lower() in (".bat", ".cmd"):
        command = ["cmd", "/c", *command]
    print("+ " + subprocess.list2cmdline(command), flush=True)
    result = subprocess.run(command, cwd=cwd, check=True, text=True, input=input_text,
                            stdout=subprocess.PIPE if capture else None)
    return result.stdout.strip() if capture else None


def run_with_retries(*command, cwd=None):
    for attempt in range(1, 4):
        try:
            run(*command, cwd=cwd)
            return
        except subprocess.CalledProcessError:
            if attempt == 3:
                raise
            print(f"Dependency sync failed; retrying ({attempt}/3)", flush=True)


def checkout(name, work):
    source = SOURCES[name]
    destination = work / ("depot_tools" if name == "depot_tools" else f"{name}-{source['commit'][:12]}")
    if not (destination / ".git").exists():
        destination.mkdir(parents=True, exist_ok=True)
        run("git", "init", destination)
        run("git", "-C", destination, "remote", "add", "origin", source["url"])
        run("git", "-C", destination, "-c", "core.longpaths=true", "fetch", "--depth", "1", "origin", source["commit"])
        run("git", "-C", destination, "-c", "core.longpaths=true", "checkout", "--detach", "FETCH_HEAD")
    if run("git", "-C", destination, "rev-parse", "HEAD", capture=True) != source["commit"]:
        raise RuntimeError(f"Unexpected revision in {destination}")
    return destination


def prepare_depot_tools(work, system):
    os.environ.update(DEPOT_TOOLS_UPDATE="0", DEPOT_TOOLS_WIN_TOOLCHAIN="0")
    depot = checkout("depot_tools", work)
    os.environ["PATH"] = str(depot) + os.pathsep + os.environ["PATH"]
    if system == "win":
        run("cmd", "/c", depot / "bootstrap/win_tools.bat", cwd=depot)
        if not (depot / "git.bat").is_file():
            raise RuntimeError("depot_tools bootstrap did not generate git.bat")


def sync_skia_deps(source):
    sync_script = source / "tools/git-sync-deps"
    content = sync_script.read_text()
    marker = "  multithread(git_checkout_to_directory, list_of_arg_lists)"
    replacement = "  for args in list_of_arg_lists:\n    git_checkout_to_directory(*args)"
    if content.count(marker) == 1:
        sync_script.write_text(content.replace(marker, replacement))
    elif replacement not in content:
        raise RuntimeError("Skia dependency sync changed; review the serial checkout patch")
    run_with_retries(sys.executable, sync_script, cwd=source)


def gn_value(value):
    return json.dumps(value).replace("$", "\\$")


def skia_args(rid):
    system, arch = rid.split("-")
    options = dict(
        target_os={"osx": "mac"}.get(system, system), target_cpu=arch,
        is_official_build=True, is_static_skiasharp=True, skia_enable_tools=False,
        skia_enable_ganesh=True, skia_enable_pdf=False, skia_enable_skottie=True,
        skia_use_dng_sdk=False, skia_use_piex=False, skia_use_harfbuzz=False,
        skia_use_icu=False, skia_use_partition_alloc=False, skia_use_vulkan=False,
        skia_use_fontconfig=system == "linux", skia_use_freetype=system in ("linux", "android"),
        skia_use_metal=system == "osx", skia_use_xps=system == "win",
        extra_cflags=["-DSKIA_C_DLL", "-DHB_NO_PRAGMA_GCC_DIAGNOSTIC_ERROR"],
        extra_cflags_cc=["/GR"] if system == "win" else ["-frtti"],
    )
    for dependency in ("expat", "libjpeg_turbo", "libpng", "libwebp", "zlib"):
        options[f"skia_use_system_{dependency}"] = False
    if options["skia_use_freetype"]:
        options["skia_use_system_freetype2"] = False
    if system != "win":
        options.update(cc="clang", cxx="clang++", ar=os.environ.get("LLVM_AR", "llvm-ar"))
        options["extra_cflags"] += ["-fPIC"]
    if system in ("linux", "android"):
        options["extra_cflags"] += ["-DHAVE_SYSCALL_GETRANDOM", "-DXML_DEV_URANDOM"]
    if system == "android":
        options.update(ndk=Path(os.environ["ANDROID_NDK_HOME"]).as_posix(), ndk_api=27)
    elif system == "osx":
        options["min_macos_version"] = "11.0"
    elif system == "win":
        options.update(is_clang=True, win_vc=(Path(os.environ["VSINSTALLDIR"]) / "VC").as_posix())
        options["clang_win"] = Path(shutil.which("clang-cl")).parent.parent.as_posix()
        options["extra_cflags"] += ["/MT"]
    return options


def angle_args(rid):
    system, arch = rid.split("-")
    options = dict(
        target_os={"osx": "mac"}.get(system, system), target_cpu=arch,
        is_debug=False, is_component_build=False, is_clang=True,
        use_custom_libcxx=False, use_thin_lto=False, use_lld=False,
        symbol_level=0, treat_warnings_as_errors=False,
        angle_build_tests=False, build_angle_deqp_tests=False,
        angle_enable_swiftshader=False, angle_enable_vulkan=False,
        angle_enable_wgpu=False, angle_enable_cl=False, angle_use_wayland=False,
    )
    if system == "linux":
        options.update(use_sysroot=False, is_clang=arch != "arm64")
    elif system == "osx":
        options.update(mac_deployment_target="11.0", use_system_xcode=True)
    elif system == "android":
        options.update(android_ndk_api_level=27, default_min_sdk_version=27,
                       android_static_analysis="off")
    return options


def build_gn(source, rid, options, targets, gn, jobs):
    output = source / "out" / f"lightstudio-{rid}"
    output.mkdir(parents=True, exist_ok=True)
    (output / "args.gn").write_text("".join(f"{key} = {gn_value(value)}\n" for key, value in options.items()))
    run(gn, "gen", output, cwd=source)
    run("ninja", "-C", output, "-j", jobs, *targets, cwd=source)
    return output


def stage_archive(build, name, destination):
    candidates = [build / name, build / "obj" / name, *sorted((build / "obj").glob(f"*/{name}"))]
    archive = next((candidate for candidate in candidates if candidate.is_file()), None)
    if archive is None:
        raise RuntimeError(f"Missing archive {name} under {build}")
    target = destination / name
    with archive.open("rb") as stream:
        magic = stream.read(8)
    if magic == b"!<thin>\n":
        target.unlink(missing_ok=True)
        run(os.environ.get("LLVM_AR", "llvm-ar"), "-M", cwd=build,
            input_text=f'CREATE "{target.as_posix()}"\nADDLIB "{archive.as_posix()}"\nSAVE\nEND\n')
    elif magic == b"!<arch>\n":
        shutil.copy2(archive, target)
    else:
        raise RuntimeError(f"Not an archive: {archive}")
    with target.open("rb") as stream:
        if stream.read(8) != b"!<arch>\n":
            raise RuntimeError(f"Archive is not self-contained: {target}")


def patch_angle(source):
    build_file = source / "BUILD.gn"
    content = build_file.read_text()
    marker = 'angle_static_library("libGLESv2_static") {\n'
    replacement = ('angle_static_library("libANGLE_static") {\n'
                   '  complete_static_lib = true\n  public_deps = [ ":libANGLE" ]\n}\n\n'
                   + marker + '  complete_static_lib = true\n')
    if 'angle_static_library("libANGLE_static")' not in content:
        if content.count(marker) != 1:
            raise RuntimeError("ANGLE static target changed; review archive patch")
        build_file.write_text(content.replace(marker, replacement))


def prepare_angle(source, system):
    excluded = ["third_party/catapult", "third_party/dawn", "third_party/llvm/src", "third_party/SwiftShader", "third_party/VK-GL-CTS/src"]
    if system == "android":
        excluded.remove("third_party/catapult")
        excluded.append("third_party/android_toolchain/ndk")
    solution = dict(name=".", url=SOURCES["angle"]["url"], managed=False,
                    custom_deps={dependency: None for dependency in excluded},
                    custom_vars=dict(checkout_angle_dawn_deps=False, checkout_angle_cl_deps=False))
    (source / ".gclient").write_text(f"solutions = {repr([solution])}\ntarget_os = {repr(['android'] if system == 'android' else [])}\n")
    config = source / "build/config/android/config.gni"
    original_ndk = '  android_ndk_root = "//third_party/android_toolchain/ndk"'
    if system == "android":
        custom_ndk = '  android_ndk_root = ' + gn_value(Path(os.environ["ANDROID_NDK_HOME"]).resolve().as_posix())
        if config.exists():
            config.write_text(config.read_text().replace(custom_ndk, original_ndk))
    run_with_retries("gclient", "sync", "--no-history", "--jobs", "1", cwd=source)
    patch_angle(source)
    translator = source / "src/compiler/translator/IntermNode.cpp"
    content = translator.read_text()
    content = content.replace("new TConstantUnion[checkedArraySize.ValueOrDie()]",
                              "new TConstantUnion[static_cast<size_t>(checkedArraySize.ValueOrDie())]")
    translator.write_text(content)
    if system == "android":
        content = config.read_text()
        if original_ndk not in content:
            raise RuntimeError("Chromium Android NDK path changed; review the r28c override")
        config.write_text(content.replace(original_ndk, custom_ndk))


def copy_licenses(source, destination):
    count = 0
    for directory, folders, files in os.walk(source):
        folders[:] = [folder for folder in folders if folder not in (".git", "out", "node_modules")]
        for filename in files:
            if filename.lower().startswith(("license", "licence", "copying", "notice")):
                path = Path(directory) / filename
                if path.is_symlink():
                    continue
                target = destination / path.relative_to(source)
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(path, target)
                count += 1
    if not count:
        raise RuntimeError(f"No license notices found in {source}")


def build_macos_native(rid, work, destination, jobs):
    source = checkout("avalonia", work)
    native = source / "native/Avalonia.Native"
    run("dotnet", "build", native / "Avalonia.Native.macOS.proj", "-t:GenerateMicroComItems", cwd=source)
    arch = "arm64" if rid.endswith("arm64") else "x86_64"
    build = work / f"avalonia-native-{rid}"
    run("xcodebuild", "-project", native / "src/OSX/Avalonia.Native.OSX.xcodeproj",
        "-target", "Avalonia.Native.OSX", "-configuration", "Release", "-sdk", "macosx", "-arch", arch,
        f"CONFIGURATION_BUILD_DIR={build}", "ONLY_ACTIVE_ARCH=NO", "CODE_SIGNING_ALLOWED=NO",
        "MACH_O_TYPE=staticlib", "EXECUTABLE_PREFIX=lib", "EXECUTABLE_EXTENSION=a",
        "PRODUCT_NAME=AvaloniaNative", f"HEADER_SEARCH_PATHS={native / 'inc'}",
        "MACOSX_DEPLOYMENT_TARGET=11.0", "CLANG_ENABLE_MODULES=YES", "GCC_GENERATE_DEBUGGING_SYMBOLS=NO",
        "-jobs", jobs, cwd=source)
    stage_archive(build, "libAvaloniaNative.a", destination)
    run("xcrun", "clang", "-arch", arch, "-mmacosx-version-min=11.0", "-fobjc-arc", "-c",
        CONFIG / "macos_font_preinit.m", "-o", destination / "macos_font_preinit.o")
    copy_licenses(source, destination / "licenses/avalonia")


def main():
    parser = argparse.ArgumentParser(description="Build LightStudio.AvaloniaStatic native archives")
    parser.add_argument("rid", choices=RIDS)
    parser.add_argument("--work-dir", type=Path, default=ROOT / "artifacts/build/avalonia-static")
    parser.add_argument("--output-dir", type=Path, default=ROOT / "artifacts")
    args = parser.parse_args()
    system = args.rid.split("-")[0]
    expected_host = {"win": "Windows", "osx": "Darwin", "linux": "Linux", "android": "Linux"}[system]
    if platform.system() != expected_host:
        parser.error(f"{args.rid} requires a {expected_host} build host")
    if system == "linux" and (platform.machine() in ("aarch64", "arm64")) != args.rid.endswith("arm64"):
        parser.error("Linux builds require a matching host architecture")
    work = args.work_dir.resolve()
    work.mkdir(parents=True, exist_ok=True)
    destination = args.output_dir.resolve() / f"avalonia-static-{args.rid}"
    destination.mkdir(parents=True, exist_ok=True)
    jobs = os.environ.get("JOBS", str(os.cpu_count() or 1))
    if system == "win":
        os.environ["GYP_MSVS_OVERRIDE_PATH"] = os.environ["VSINSTALLDIR"].rstrip("\\/")
        os.environ["GYP_MSVS_VERSION"] = "2022"
    prepare_depot_tools(work, system)
    skia_sharp = checkout("skiasharp", work)
    run("git", "-C", skia_sharp, "submodule", "update", "--init", "--depth", "1", "externals/skia")
    skia = skia_sharp / "externals/skia"
    sync_skia_deps(skia)
    gn = skia / "bin" / ("gn.exe" if system == "win" else "gn")
    build = build_gn(skia, args.rid, skia_args(args.rid), ["skia", "SkiaSharp", "HarfBuzzSharp"], gn, jobs)
    skia_components = ["skia", "SkiaSharp", "HarfBuzzSharp", "skottie", "skresources", "sksg", "skshaper", "jsonreader"]
    skia_names = [f"{name}.lib" if system == "win" else f"lib{name}.a" for name in skia_components]
    for name in skia_names:
        stage_archive(build, name, destination)
    if system == "win":
        (destination / "HarfBuzzSharp.lib").replace(destination / "libHarfBuzzSharp.lib")
    shutil.copy2(build / "args.gn", destination / "skia-args.gn")
    copy_licenses(skia_sharp, destination / "licenses/skiasharp")

    angle = checkout("angle", work)
    prepare_angle(angle, system)
    build = build_gn(angle, args.rid, angle_args(args.rid), ["libANGLE_static", "libGLESv2_static"], "gn", jobs)
    for name in ("libANGLE_static", "libGLESv2_static"):
        stage_archive(build, name + (".lib" if system == "win" else ".a"), destination)
    shutil.copy2(build / "args.gn", destination / "angle-args.gn")
    copy_licenses(angle, destination / "licenses/angle")
    if system == "osx":
        build_macos_native(args.rid, work, destination, jobs)
    metadata = dict(rid=args.rid, skiasharp="4.153.1", harfbuzz="14.2.1", harfbuzzsharp="14.2.1.301",
                    avalonia="12.1.3", sources=SOURCES, android_api=27, macos_minimum="11.0",
                    linux_build="Ubuntu 24.04", windows_minimum="10", jobs=jobs)
    metadata["skia_commit"] = run("git", "-C", skia, "rev-parse", "HEAD", capture=True)
    metadata["harfbuzz_commit"] = run("git", "-C", skia / "third_party/externals/harfbuzz", "rev-parse", "HEAD", capture=True)
    (destination / "build-info.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(f"Staged {args.rid} in {destination}")


if __name__ == "__main__":
    main()
