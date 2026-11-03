#!/usr/bin/env python3
"""
btquery.py - Fast JSON status extractor for Bluetooth in Edots Quickshell.
Queries bluetoothctl safely and returns structured JSON output.
"""

import sys
import subprocess
import json
import shutil

def main():
    if not shutil.which("bluetoothctl"):
        print(json.dumps({"available": False, "powered": False, "discovering": False, "adapter": "", "devices": []}))
        return

    try:
        show = subprocess.check_output(["bluetoothctl", "show"], text=True, stderr=subprocess.DEVNULL, timeout=2)
    except Exception:
        print(json.dumps({"available": False, "powered": False, "discovering": False, "adapter": "", "devices": []}))
        return

    powered = "Powered: yes" in show
    discovering = "Discovering: yes" in show
    adapter_name = ""
    for line in show.splitlines():
        line = line.strip()
        if line.startswith("Name: "):
            adapter_name = line.split("Name: ", 1)[1]
            break

    devices = []
    if powered:
        try:
            dev_lines = subprocess.check_output(["bluetoothctl", "devices"], text=True, stderr=subprocess.DEVNULL, timeout=2).splitlines()
        except Exception:
            dev_lines = []

        for line in dev_lines:
            parts = line.strip().split(" ", 2)
            if len(parts) >= 2 and parts[0] == "Device":
                mac = parts[1]
                name = parts[2] if len(parts) > 2 else mac
                try:
                    info = subprocess.check_output(["bluetoothctl", "info", mac], text=True, stderr=subprocess.DEVNULL, timeout=1.5)
                except Exception:
                    info = ""

                connected = "Connected: yes" in info
                paired = "Paired: yes" in info
                trusted = "Trusted: yes" in info
                blocked = "Blocked: yes" in info
                icon = "bluetooth"
                battery = -1

                for iline in info.splitlines():
                    iline = iline.strip()
                    if iline.startswith("Icon: "):
                        icon = iline.split("Icon: ", 1)[1]
                    elif iline.startswith("Battery Percentage: "):
                        try:
                            # format: Battery Percentage: 0x32 (50)
                            val = iline.split("(")[1].split(")")[0]
                            battery = int(val)
                        except Exception:
                            pass

                devices.append({
                    "mac": mac,
                    "name": name,
                    "connected": connected,
                    "paired": paired,
                    "trusted": trusted,
                    "blocked": blocked,
                    "icon": icon,
                    "battery": battery
                })

    print(json.dumps({
        "available": True,
        "powered": powered,
        "discovering": discovering,
        "adapter": adapter_name,
        "devices": devices
    }))

if __name__ == "__main__":
    main()
