# jetson-containers

The PyPI distribution for
[`jetson-ai-lab/jetson-containers`](https://github.com/jetson-ai-lab/jetson-containers)
— installs the `jetson` console command.

This **v0.0.1** release is a name-claim stub. The repository itself (build/run
scripts, package definitions, Dockerfiles) remains the canonical source of the
`jetson-containers` tooling; pip-installable features will ship in later
releases.

## Install

```bash
pip install jetson-containers
jetson --version
jetson x
```

## Note

`jetson-containers` and [`jetson-cli`](https://pypi.org/project/jetson-cli/)
ship identical code in this release. The bash `jetson-containers` dispatcher
inside the repository (installed by `install.sh` to `/usr/local/bin/jetson-containers`)
is a separate tool and is not affected by this package.
