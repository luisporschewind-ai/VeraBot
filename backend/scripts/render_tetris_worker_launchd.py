"""Render a reviewable launchd file. Never installs or starts a job."""
import argparse
from pathlib import Path
import plistlib
import re

def render(backend, python, database, log_dir, label="com.verabot.tetris-worker"):
    paths = [Path(value) for value in (backend, python, database, log_dir)]
    if any(not path.is_absolute() for path in paths):
        raise ValueError("all paths must be absolute")
    backend, python, database, log_dir = paths
    if not (backend / "verabot" / "services" / "tetris_sessions" / "__main__.py").is_file():
        raise ValueError("backend must contain the reviewed Tetris worker")
    if not python.is_file() or not database.is_file() or not log_dir.is_dir():
        raise ValueError("Python, migrated database and existing log directory are required")
    if not re.fullmatch(r"[a-zA-Z0-9.-]+", label):
        raise ValueError("invalid launchd label")
    return plistlib.dumps({
        "Label": label,
        "ProgramArguments": [str(python), "-m", "verabot.services.tetris_sessions"],
        "WorkingDirectory": str(backend),
        "EnvironmentVariables": {"VERABOT_DB": str(database), "PYTHONUNBUFFERED": "1"},
        "RunAtLoad": True, "KeepAlive": True, "ThrottleInterval": 5,
        "ProcessType": "Background", "ExitTimeOut": 15,
        "StandardOutPath": str(log_dir / "tetris-worker.log"),
        "StandardErrorPath": str(log_dir / "tetris-worker-error.log"),
    }, sort_keys=True)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("backend", "python", "database", "log-dir", "output"):
        parser.add_argument("--" + name, required=True, type=Path)
    parser.add_argument("--label", default="com.verabot.tetris-worker")
    args = parser.parse_args()
    payload = render(args.backend, args.python, args.database, args.log_dir, args.label)
    # Exclusive creation prevents silently replacing an active service definition.
    with args.output.open("xb") as target:
        target.write(payload)
    print(args.output)
if __name__ == "__main__": main()
