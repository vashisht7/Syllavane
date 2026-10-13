"""Compatibility entry point for the expansion regression test (no copy-edit fallback)."""
import pathlib,runpy
runpy.run_path(str(pathlib.Path(__file__).with_name("expansion-smoke.py")),run_name="__main__")
