"""Minimal `jetson` CLI. v0.0.1 exists only to claim the PyPI names."""
from __future__ import annotations

import argparse
import sys

from jetson_cli import __version__


def _cmd_x(args: argparse.Namespace) -> int:
    print("jetson: ok")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="jetson",
        description="Jetson CLI (stub v0.0.1 — full functionality coming soon).",
    )
    parser.add_argument(
        "--version",
        action="version",
        version=f"jetson {__version__}",
    )
    sub = parser.add_subparsers(dest="command", metavar="<command>")

    p_x = sub.add_parser("x", help="smoke-test subcommand (prints 'jetson: ok')")
    p_x.set_defaults(func=_cmd_x)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if not getattr(args, "func", None):
        parser.print_help()
        return 0
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
