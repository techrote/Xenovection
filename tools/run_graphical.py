#!/usr/bin/env python3
"""Run a real X11 Godot render with an isolated software-display lifetime.

Xorg and Godot are children of this one process, also suitable for environments
with separate network namespaces per command. This is graphical execution, not
Godot's dummy --headless driver. Mesa software timings are not target-GPU claims.
"""
from __future__ import annotations
import argparse
import os
from pathlib import Path
import random
import socket
import subprocess
import tempfile
import time


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--engine", default="godot")
    parser.add_argument("--icd", type=Path)
    parser.add_argument("--library-path", type=Path)
    parser.add_argument("--timeout", type=int, default=600)
    parser.add_argument("--log", type=Path)
    parser.add_argument("args", nargs=argparse.REMAINDER)
    options = parser.parse_args()
    arguments = options.args[1:] if options.args[:1] == ["--"] else options.args
    with tempfile.TemporaryDirectory(prefix="xenovection-display-") as temp:
        folder = Path(temp)
        config = folder / "xorg.conf"
        config.write_text('''Section "ServerFlags"
 Option "AutoAddDevices" "false"
 Option "AutoEnableDevices" "false"
 Option "DontVTSwitch" "true"
EndSection
Section "Device"
 Identifier "Dummy"
 Driver "dummy"
 VideoRam 256000
EndSection
Section "Monitor"
 Identifier "Monitor"
 HorizSync 5.0-1000.0
 VertRefresh 5.0-200.0
EndSection
Section "Screen"
 Identifier "Screen"
 Device "Dummy"
 Monitor "Monitor"
 DefaultDepth 24
 SubSection "Display"
  Depth 24
  Virtual 2048 1536
 EndSubSection
EndSection
''')
        display = random.randrange(210, 480)
        xlog = options.log or folder / "xorg.log"
        xlog.parent.mkdir(parents=True, exist_ok=True)
        server = subprocess.Popen(["Xorg", f":{display}", "-config", str(config),
                                   "-noreset", "-nolisten", "local", "-nolisten", "unix",
                                   "-listen", "tcp", "-ac", "-logfile", str(xlog)],
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            for _ in range(100):
                if server.poll() is not None:
                    raise RuntimeError(f"Xorg exited {server.returncode}: {xlog.read_text()[-5000:]}")
                try:
                    with socket.create_connection(("127.0.0.1", 6000 + display), timeout=.1):
                        break
                except OSError:
                    time.sleep(.1)
            else:
                raise RuntimeError("Xorg did not open its local display")
            environment = os.environ.copy()
            environment["DISPLAY"] = f"127.0.0.1:{display}"
            environment["LIBGL_ALWAYS_SOFTWARE"] = "1"
            environment["LP_NUM_THREADS"] = "4"
            if options.icd:
                environment["VK_ICD_FILENAMES"] = str(options.icd.resolve())
            if options.library_path:
                environment["LD_LIBRARY_PATH"] = str(options.library_path.resolve()) + os.pathsep + environment.get("LD_LIBRARY_PATH", "")
            result = subprocess.run([options.engine, *arguments], env=environment, timeout=options.timeout)
            return result.returncode
        finally:
            server.terminate()
            try:
                server.wait(5)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait()


if __name__ == "__main__":
    raise SystemExit(main())
