#!/usr/bin/env python3
"""Install a source-owned Brahma class directory without replacing user content."""
import argparse
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


def default_extensions():
    if sys.platform == "darwin":
        return Path.home() / "Library/Application Support/SuperCollider/Extensions"
    return Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "SuperCollider/Extensions"


def installed_class_paths(root, owned_destination):
    """Inspect aliases like SC does, with cycle protection and no mutation."""
    pending, visited = [root], set()
    while pending:
        directory = pending.pop()
        if directory == owned_destination:
            continue
        resolved = directory.resolve()
        if resolved in visited:
            continue
        visited.add(resolved)
        for path in sorted(directory.iterdir()):
            if path == owned_destination:
                continue
            if path.is_dir():
                pending.append(path)
            elif path.suffix == ".sc":
                yield path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="apply the inspected link changes")
    parser.add_argument("--verify", action="store_true", help="compile classes in a bounded native interpreter after installation")
    parser.add_argument("--source", type=Path, default=Path(__file__).resolve().parents[1] / "brahma/sc")
    parser.add_argument("--extensions-dir", type=Path, default=default_extensions())
    args = parser.parse_args()
    if args.verify and not args.apply:
        parser.error("--verify requires --apply")
    source = args.source.resolve()
    classes = sorted(source.rglob("*.sc"))
    if not (source / "BrahmaMetrics.sc").is_file() or not (source / "AdamKadmon.sc").is_file():
        parser.error("source must contain the Brahma classes")
    names = {path.name: path for path in classes}
    if len(names) != len(classes) or any(not re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*", path.stem) for path in classes):
        parser.error("class filenames must be unique valid class identifiers")
    root = args.extensions_dir.expanduser().absolute()
    destination = root / "Brahma"
    owned_directory = destination.is_symlink() and destination.resolve() == source
    if (destination.exists() or destination.is_symlink()) and not owned_directory:
        parser.exit(1, f"Refusing to replace existing content: {destination}\n")
    legacy = []
    # Preflight every collision before changing any path. Only the exact links
    # created by the previous per-file installer are eligible for removal.
    try:
        existing = sorted(installed_class_paths(root, destination)) if root.exists() else []
    except (OSError, RuntimeError) as error:
        parser.exit(1, f"Refusing installation because extension inspection failed: {error}\n")
    for path in existing:
        if path.name not in names:
            continue
        if path.parent == root and path.is_symlink() and path.resolve() == names[path.name]:
            legacy.append(path)
        else:
            parser.exit(1, f"Refusing duplicate/foreign class content: {path}\n")
    if args.apply:
        root.mkdir(parents=True, exist_ok=True)
        if not owned_directory:
            destination.symlink_to(source, target_is_directory=True)
        for path in legacy:
            path.unlink()
            print(f"REMOVED owned legacy link {path}")
        print(f"OK {destination} -> {source} ({len(classes)} recursive classes)")
    else:
        for path in legacy:
            print(f"WOULD REMOVE owned legacy link {path}")
        print(f"{'OK' if owned_directory else 'WOULD CREATE'} {destination} -> {source} ({len(classes)} recursive classes)")
    if args.verify:
        runner = Path(__file__).with_name("test-supercollider.py")
        with tempfile.TemporaryDirectory(prefix="brahma-install-check-") as directory:
            driver = Path(directory) / "verify.scd"
            symbols = ", ".join("\\" + path.stem for path in classes)
            driver.write_text("(\ntry {\n[" + symbols + "].do { |name|\n"
                              "    if(name.asClass.isNil) { Error(\"Missing class: \" ++ name).throw };\n"
                              "};\n\"BRAHMA_TEST_PASS\".postln; 0.exit;\n"
                              "} { |error| error.reportError; 1.exit };\n)\n")
            result = subprocess.run([sys.executable, str(runner), str(driver), "--source", str(source)], check=False)
            if result.returncode:
                return result.returncode
            print("RECOMPILE OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
