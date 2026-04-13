#!/usr/bin/env bash
set -euo pipefail

rustc --version
cargo --version
python3 -c "import setuptools_rust; print('setuptools_rust', setuptools_rust.__version__)"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cd "$tmp"
cargo new --quiet hello
cd hello
cargo build --quiet --release
out=$(./target/release/hello)
echo "$out"
[[ "$out" == "Hello, world!" ]]
echo "OK"
