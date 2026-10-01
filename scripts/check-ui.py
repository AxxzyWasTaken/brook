#!/usr/bin/env python3
"""Build and check the real AppKit controls using isolated, synthetic browser state."""

import argparse
import json
import os
import pathlib
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--objects", type=pathlib.Path, help="Use existing Release object files instead of building")
parser.add_argument("--output", type=pathlib.Path, help="Keep captures and benchmark samples in this directory")
parser.add_argument("--baseline", action="store_true", help="Check the original implementation without optimization assertions")
parser.add_argument("--browser", action="store_true", help="Check history search and complete browser actions using local data")
parser.add_argument("--startup", action="store_true", help="Measure startup in fresh processes: 2 warmups and 9 samples")
parser.add_argument("--runs", type=int, default=15, help="Measured samples per workload (default: 15)")
parser.add_argument("--warmups", type=int, default=4, help="Warmup samples per workload (default: 4)")
parser.add_argument("--compile-only", action="store_true", help="Save the test executable in --output for paired process runs")
parser.add_argument("--paired-baseline", type=pathlib.Path, help="Compare all suites with these baseline object files")
parser.add_argument("--pairs", type=int, default=6, help="Alternating before/after process pairs (default: 6)")
parser.add_argument("--allow-visible-tests", action="store_true", help="Explicitly permit foreground window changes and animations")
parser.add_argument("--offscreen", action="store_true", help="Block window presentation and activation; exclude live frame pacing")
args = parser.parse_args()
if args.offscreen and args.allow_visible_tests:
    parser.error("--offscreen cannot be combined with --allow-visible-tests")
if (args.browser or args.startup or args.paired_baseline) and not args.compile_only and not args.allow_visible_tests and not args.offscreen:
    parser.error("Visible browser/startup tests are disabled. Obtain explicit approval before using --allow-visible-tests.")
if not 1 <= args.runs <= 1000 or not 0 <= args.warmups <= 100:
    parser.error("--runs must be 1–1000 and --warmups must be 0–100")
if args.compile_only and not args.output:
    parser.error("--compile-only requires --output")
if args.paired_baseline and (not args.output or args.compile_only or args.browser or args.startup or args.baseline):
    parser.error("--paired-baseline requires --output and cannot be combined with individual suite modes")
if not 2 <= args.pairs <= 30:
    parser.error("--pairs must be 2–30")
if args.browser and args.startup:
    parser.error("Choose either --browser or --startup")
root = pathlib.Path(__file__).resolve().parent.parent

with tempfile.TemporaryDirectory(prefix="brook-ui-check-") as temporary:
    temporary = pathlib.Path(temporary)
    objects = args.objects
    if objects is None:
        with (temporary / "build.log").open("w+") as log:
            try:
                subprocess.run(["xcodegen", "generate"], cwd=root, stdout=log, stderr=log, check=True)
                subprocess.run(["xcodebuild", "-project", "Brook.xcodeproj", "-scheme", "Brook", "-configuration", "Release",
                                "-derivedDataPath", "build", "CODE_SIGN_IDENTITY=-", "build"],
                               cwd=root, stdout=log, stderr=log, check=True)
            except subprocess.CalledProcessError:
                log.seek(0)
                print(log.read())
                raise
        objects = root / "build/Build/Intermediates.noindex/Brook.build/Release/Brook.build/Objects-normal/arm64"
    files = sorted(str(p.resolve()) for p in objects.glob("*.o") if p.name != "main.o")
    if not files:
        parser.error(f"No object files found in {objects}")
    command = ["xcrun", "clang++", "-std=c++23", "-O2", "-fobjc-arc", "-fmodules", "-Wno-deprecated-declarations"]
    for directory in sorted((root / "Sources").iterdir()):
        if directory.is_dir():
            command += ["-I", str(directory)]
    command += [str(root / "scripts/check-ui.mm"), *files]
    for framework in ["AppKit", "WebKit", "QuartzCore", "CoreGraphics", "Security", "LocalAuthentication",
                      "UniformTypeIdentifiers", "UserNotifications"]:
        command += ["-framework", framework]
    executable = temporary / "check-ui"
    subprocess.run([*command, "-lsqlite3", "-o", str(executable)], check=True)
    output = args.output.resolve() if args.output else temporary / "results"
    if args.compile_only:
        output.mkdir(parents=True, exist_ok=True)
        shutil.copy2(executable, output / "check-ui")
        raise SystemExit(0)
    environment = {**os.environ, "BROOK_CHECK_RUNS": str(args.runs), "BROOK_CHECK_WARMUPS": str(args.warmups),
                   "BROOK_ALLOW_VISIBLE_TESTS": "1" if args.allow_visible_tests else "0"}
    if args.paired_baseline:
        baseline_files = sorted(str(p.resolve()) for p in args.paired_baseline.glob("*.o") if p.name != "main.o")
        if not baseline_files:
            parser.error(f"No baseline object files found in {args.paired_baseline}")
        baseline_command = [part for part in command if part not in files]
        baseline_executable = temporary / "check-ui-baseline"
        subprocess.run([*baseline_command, *baseline_files, "-lsqlite3", "-o", str(baseline_executable)], check=True)
        output.mkdir(parents=True, exist_ok=True)
        evidence = {"protocol": {"pairs": args.pairs, "runs": args.runs, "warmups": args.warmups,
                                 "order": "AB then BA, alternating", "startup_runs": 30, "startup_warmups": 4,
                                 "offscreen": args.offscreen},
                    "trials": [], "startup": {"before": [], "after": []}}
        executables = {"before": baseline_executable, "after": executable}
        def save():
            (output / "paired-results.json").write_text(json.dumps(evidence, indent=2) + "\n")
        for pair in range(args.pairs):
            order = ("before", "after") if pair % 2 == 0 else ("after", "before")
            for suite in ("ui", "browser"):
                for variant in order:
                    destination = output / f"{pair}-{suite}-{variant}"
                    destination.mkdir()
                    with (destination / "run.log").open("w") as log:
                        subprocess.run([str(executables[variant]), str(destination),
                                        *(["--baseline"] if variant == "before" else []),
                                        *(["--offscreen"] if args.offscreen else []),
                                        *(["--browser"] if suite == "browser" else [])],
                                       env=environment, stdout=log, stderr=log, check=True, timeout=1200)
                    samples = json.loads((destination / ("timings.json" if suite == "ui" else "browser-timings.json")).read_text())
                    assert all(len(values) == args.runs for values in samples.values())
                    evidence["trials"].append({"pair": pair, "suite": suite, "variant": variant,
                                               "directory": destination.name, "samples": samples})
                    save()
                    print(f"Pair {pair + 1}/{args.pairs}: {suite} {variant} passed", flush=True)
        bundle = root / "build/Build/Products/Release/Brook.app"
        for run in range(34):
            order = ("before", "after") if run % 2 == 0 else ("after", "before")
            for variant in order:
                destination = output / f"startup-{run}-{variant}"
                destination.mkdir()
                with (destination / "run.log").open("w") as log:
                    subprocess.run([str(executables[variant]), str(destination), "--startup", *(["--offscreen"] if args.offscreen else [])],
                                   env={**environment, "BROOK_UI_CHECK_BUNDLE": str(bundle)},
                                   stdout=log, stderr=log, check=True, timeout=90)
                if run >= 4:
                    value = json.loads((destination / "startup.json").read_text())["startup_to_first_window_submission_ms"]
                    evidence["startup"][variant].append(value)
            save()
        print("All paired suites and 30 measured startup pairs passed.", flush=True)
    elif args.startup:
        bundle = root / "build/Build/Products/Release/Brook.app"
        if not bundle.is_dir():
            parser.error("Build the Release app first; the startup check uses its bundled resources")
        output.mkdir(parents=True, exist_ok=True)
        samples = []
        for run in range(11):
            destination = temporary / f"startup-{run}"
            subprocess.run([str(executable), str(destination), "--startup", *(["--offscreen"] if args.offscreen else [])], check=True,
                           env={**environment, "BROOK_UI_CHECK_BUNDLE": str(bundle)})
            result = json.loads((destination / "startup.json").read_text())
            if run >= 2:
                samples.append(result["startup_to_first_window_submission_ms"])
        (output / "startup-timings.json").write_text(json.dumps({"warmups": 2, "samples_ms": samples}, indent=2) + "\n")
    else:
        subprocess.run([str(executable), str(output), *(["--baseline"] if args.baseline else []),
                        *(["--offscreen"] if args.offscreen else []),
                        *(["--browser"] if args.browser else [])], check=True, env=environment)
