#!/usr/bin/env python
import glob
import os
import sys
from pathlib import Path


def _add_local_libpq_to_path():
    """Windows-only: let psycopg's ctypes loader find libpq.dll from a local
    PostgreSQL install, since the venv's own psycopg-binary DLL can get
    blocked by Windows Application Control on this machine."""
    if sys.platform != "win32":
        return
    for pattern in (
        r"C:\Program Files\PostgreSQL\*\bin",
        r"C:\Program Files (x86)\PostgreSQL\*\bin",
    ):
        for bin_dir in sorted(glob.glob(pattern), reverse=True):
            if os.path.isfile(os.path.join(bin_dir, "libpq.dll")):
                os.add_dll_directory(bin_dir)
                os.environ["PATH"] = bin_dir + os.pathsep + os.environ.get("PATH", "")
                return


def main():
    os.chdir(Path(__file__).resolve().parent)
    _add_local_libpq_to_path()
    os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings.development")
    try:
        from django.core.management import execute_from_command_line
    except ImportError as exc:
        raise ImportError("Could not import Django.") from exc
    execute_from_command_line(sys.argv)


if __name__ == "__main__":
    main()
