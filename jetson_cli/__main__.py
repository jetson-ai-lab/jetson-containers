"""Module entry point so `python -m jetson_cli` dispatches to `main()`."""
import sys

from jetson_cli.main import main

if __name__ == "__main__":
    sys.exit(main())
