"""Smoke tests for the `jetson` CLI stub."""
from __future__ import annotations

import subprocess
import sys

import pytest

from jetson_cli import __version__
from jetson_cli.main import build_parser, main


def test_version_constant():
    assert __version__ == "0.0.1"


def test_parser_version(capsys):
    parser = build_parser()
    with pytest.raises(SystemExit) as excinfo:
        parser.parse_args(["--version"])
    assert excinfo.value.code == 0
    assert "jetson 0.0.1" in capsys.readouterr().out


def test_x_subcommand(capsys):
    assert main(["x"]) == 0
    assert "jetson: ok" in capsys.readouterr().out


def test_module_entry():
    result = subprocess.run(
        [sys.executable, "-m", "jetson_cli", "--version"],
        check=True,
        capture_output=True,
        text=True,
    )
    assert "jetson 0.0.1" in result.stdout
