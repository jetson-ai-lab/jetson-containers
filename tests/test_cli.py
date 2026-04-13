"""Smoke tests for the `jetson` CLI stub."""
from __future__ import annotations

import subprocess
import sys

from cli import __version__
from cli.main import build_parser, main


def test_version_constant():
    assert __version__ == "0.0.1"


def test_parser_version(capsys):
    parser = build_parser()
    try:
        parser.parse_args(["--version"])
    except SystemExit as exc:
        assert exc.code == 0
    assert "jetson 0.0.1" in capsys.readouterr().out


def test_x_subcommand(capsys):
    assert main(["x"]) == 0
    assert "jetson: ok" in capsys.readouterr().out


def test_module_entry():
    result = subprocess.run(
        [sys.executable, "-m", "cli", "--version"],
        check=True,
        capture_output=True,
        text=True,
    )
    assert "jetson 0.0.1" in result.stdout
