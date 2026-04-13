#!/usr/bin/env python3
import importlib
import subprocess
import sys

print("python:", sys.version)
print("executable:", sys.executable)

subprocess.run([sys.executable, "-m", "pip", "--version"], check=True)

assert sys.version_info.major == 3 and sys.version_info.minor >= 8, sys.version

importlib.import_module("ssl")
importlib.import_module("sqlite3")
importlib.import_module("ctypes")

print("OK")
