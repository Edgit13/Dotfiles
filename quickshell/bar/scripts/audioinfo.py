#!/usr/bin/env python3
"""
audioinfo.py - Extract PipeWire / PulseAudio devices and streams for Edots Audio Device Manager.
Outputs sinks (outputs), sources (inputs/mics), streams (per-app volume), and default devices.
"""

import sys
import subprocess
import json

def get_audio():
    # 1. Defaults
    def_sink = ""
    def_source = ""
    try:
        def_sink = subprocess.check_output(["pactl", "get-default-sink"], text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        pass
    try:
        def_source = subprocess.check_output(["pactl", "get-default-source"], text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        pass

    # 2. Sinks (Output devices)
    sinks = []
    try:
        sinks_raw = json.loads(subprocess.check_output(["pactl", "-f", "json", "list", "sinks"], text=True, stderr=subprocess.DEVNULL))
        for s in sinks_raw:
            vol = 0
            if "volume" in s and s["volume"]:
                first_ch = list(s["volume"].values())[0]
                val_pct = first_ch.get("value_percent", "0%").replace("%", "")
                try:
                    vol = int(val_pct)
                except Exception:
                    pass
            ports = [p.get("description", p.get("name")) for p in s.get("ports", [])]
            sinks.append({
                "index": s["index"],
                "name": s["name"],
                "description": s.get("description", s["name"]),
                "volume": vol,
                "muted": s.get("mute", False),
                "isDefault": s["name"] == def_sink,
                "activePort": s.get("active_port", ""),
                "ports": ports
            })
    except Exception:
        pass

    # 3. Sources (Input devices / Microphones)
    sources = []
    try:
        sources_raw = json.loads(subprocess.check_output(["pactl", "-f", "json", "list", "sources"], text=True, stderr=subprocess.DEVNULL))
        for s in sources_raw:
            if s["name"].endswith(".monitor"):
                continue
            vol = 0
            if "volume" in s and s["volume"]:
                first_ch = list(s["volume"].values())[0]
                val_pct = first_ch.get("value_percent", "0%").replace("%", "")
                try:
                    vol = int(val_pct)
                except Exception:
                    pass
            ports = [p.get("description", p.get("name")) for p in s.get("ports", [])]
            sources.append({
                "index": s["index"],
                "name": s["name"],
                "description": s.get("description", s["name"]),
                "volume": vol,
                "muted": s.get("mute", False),
                "isDefault": s["name"] == def_source,
                "activePort": s.get("active_port", ""),
                "ports": ports
            })
    except Exception:
        pass

    # 4. Streams (Per-Application Volume)
    streams = []
    try:
        streams_raw = json.loads(subprocess.check_output(["pactl", "-f", "json", "list", "sink-inputs"], text=True, stderr=subprocess.DEVNULL))
        for st in streams_raw:
            props = st.get("properties", {})
            app_name = props.get("application.name", props.get("media.name", "Audio Stream"))
            binary = props.get("application.process.binary", "")
            vol = 0
            if "volume" in st and st["volume"]:
                first_ch = list(st["volume"].values())[0]
                val_pct = first_ch.get("value_percent", "0%").replace("%", "")
                try:
                    vol = int(val_pct)
                except Exception:
                    pass
            streams.append({
                "index": st["index"],
                "name": app_name,
                "binary": binary,
                "media": props.get("media.name", ""),
                "volume": vol,
                "muted": st.get("mute", False),
                "sink": st.get("sink", 0)
            })
    except Exception:
        pass

    return {
        "defaultSink": def_sink,
        "defaultSource": def_source,
        "sinks": sinks,
        "sources": sources,
        "streams": streams
    }

if __name__ == "__main__":
    print(json.dumps(get_audio()))
