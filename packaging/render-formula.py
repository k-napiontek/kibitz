#!/usr/bin/env python3
"""Fill in packaging/kibitz.rb.template for a release.

The formula in the tap is generated, never hand edited, so the version, the
checksums and the bottle block cannot drift from what was actually published.
"""
import argparse
import json
import pathlib
import sys

HERE = pathlib.Path(__file__).parent


def bottle_block(path: pathlib.Path) -> str:
    """Render the `bottle do` block from what `brew bottle --json` reported.

    Read rather than assumed: Homebrew works out for itself whether the build is
    relocatable, and hardcoding `any_skip_relocation` would silently ship a lie
    the day that stops being true.
    """
    data = json.loads(path.read_text())
    entry = next(iter(data.values()))["bottle"]
    lines = ["  bottle do", f'    root_url "{entry["root_url"]}"']
    for tag, meta in entry["tags"].items():
        lines.append(
            f'    sha256 cellar: :{entry["cellar"]}, {tag}: "{meta["sha256"]}"'
        )
    lines += ["  end", "", ""]
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", required=True)
    parser.add_argument("--url", required=True)
    parser.add_argument("--sha256", required=True)
    parser.add_argument("--bottle-json", type=pathlib.Path)
    args = parser.parse_args()

    formula = (HERE / "kibitz.rb.template").read_text()
    formula = formula.replace("@VERSION@", args.version)
    formula = formula.replace("@URL@", args.url)
    formula = formula.replace("@SHA256@", args.sha256)
    # Absent on the first pass, when the bottle does not exist yet and the
    # formula is only there so Homebrew can build one.
    formula = formula.replace(
        "@BOTTLE@\n", bottle_block(args.bottle_json) if args.bottle_json else ""
    )
    sys.stdout.write(formula)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
