#!/usr/bin/env python3
"""Socket/SSE contract suite for protocol-v2 group execution against a local fake server."""
from pathlib import Path
import runpy

runpy.run_path(str(Path(__file__).with_name("group_http_test.py")), run_name="__main__")
