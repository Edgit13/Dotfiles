#!/usr/bin/env python3
"""
netinfo.py - Extract network details for Edots Quickshell Network Manager+.
Gathers Ethernet info, VPN connections, saved connections, IP/Gateway/DNS, and connection diagnostics.
"""

import sys
import subprocess
import json
import os
import shutil

def get_net_info(run_ping=False):
    # 1. Devices & Ethernet
    eth_devices = []
    try:
        dev_out = subprocess.check_output(["nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device"], text=True, errors="replace", stderr=subprocess.DEVNULL)
        for line in dev_out.splitlines():
            line = line.strip()
            if not line:
                continue
            parts = line.split(":")
            if len(parts) >= 4 and parts[1] == "ethernet" and not parts[0].startswith("veth"):
                dev = parts[0]
                state = parts[2]
                conn = parts[3]
                speed = -1
                speed_path = f"/sys/class/net/{dev}/speed"
                if os.path.exists(speed_path):
                    try:
                        with open(speed_path) as f:
                            speed = int(f.read().strip())
                    except Exception:
                        pass
                eth_devices.append({
                    "device": dev,
                    "state": state,
                    "connection": conn,
                    "connected": "connected" in state.lower(),
                    "speed": speed
                })
    except Exception:
        pass

    # 2. Connections (VPN & Saved)
    vpn_conns = []
    saved_conns = []
    try:
        conn_out = subprocess.check_output(["nmcli", "-t", "-f", "NAME,TYPE,UUID,DEVICE", "connection", "show"], text=True, errors="replace", stderr=subprocess.DEVNULL)
        for line in conn_out.splitlines():
            line = line.strip()
            if not line:
                continue
            parts = line.split(":")
            if len(parts) >= 4:
                name, ctype, uuid, device = parts[0], parts[1], parts[2], parts[3]
                is_active = bool(device.strip())
                is_vpn = "vpn" in ctype.lower() or "wireguard" in ctype.lower() or "tun" in ctype.lower()
                if is_vpn:
                    vpn_conns.append({
                        "name": name,
                        "type": ctype,
                        "uuid": uuid,
                        "device": device,
                        "active": is_active
                    })
                # Saved connections (excluding loopback & docker)
                if ctype not in ("loopback", "bridge"):
                    saved_conns.append({
                        "name": name,
                        "type": ctype,
                        "uuid": uuid,
                        "device": device,
                        "active": is_active
                    })
    except Exception:
        pass

    # 3. IP, Gateway, DNS
    ip_details = {"ip": "", "gateway": "", "dns": [], "interface": ""}
    try:
        show_out = subprocess.check_output(["nmcli", "-t", "-f", "GENERAL.DEVICE,GENERAL.STATE,IP4.ADDRESS,IP4.GATEWAY,IP4.DNS", "device", "show"], text=True, errors="replace", stderr=subprocess.DEVNULL)
        cur_dev = ""
        cur_state = ""
        cur_ip = ""
        cur_gw = ""
        cur_dns = []
        for line in show_out.splitlines():
            line = line.strip()
            if not line:
                if cur_state.startswith("100") and cur_ip and not ip_details["ip"]:
                    ip_details = {"ip": cur_ip, "gateway": cur_gw, "dns": cur_dns, "interface": cur_dev}
                cur_dev, cur_state, cur_ip, cur_gw, cur_dns = "", "", "", "", []
                continue
            if line.startswith("GENERAL.DEVICE:"):
                cur_dev = line.split(":", 1)[1]
            elif line.startswith("GENERAL.STATE:"):
                cur_state = line.split(":", 1)[1]
            elif line.startswith("IP4.ADDRESS"):
                val = line.split(":", 1)[1]
                if not cur_ip:
                    cur_ip = val
            elif line.startswith("IP4.GATEWAY:"):
                cur_gw = line.split(":", 1)[1]
            elif line.startswith("IP4.DNS"):
                dns_val = line.split(":", 1)[1]
                if dns_val and dns_val not in cur_dns:
                    cur_dns.append(dns_val)
        if cur_state.startswith("100") and cur_ip and not ip_details["ip"]:
            ip_details = {"ip": cur_ip, "gateway": cur_gw, "dns": cur_dns, "interface": cur_dev}
    except Exception:
        pass

    # 4. Optional Ping Diagnostics
    diag = {"tested": False, "gateway_ok": False, "internet_ok": False, "latency": -1.0}
    if run_ping:
        diag["tested"] = True
        # Ping gateway if available
        gw = ip_details.get("gateway")
        if gw:
            try:
                res = subprocess.run(["ping", "-c", "1", "-W", "1", gw], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                diag["gateway_ok"] = (res.returncode == 0)
            except Exception:
                pass
        # Ping 1.1.1.1
        try:
            out = subprocess.check_output(["ping", "-c", "1", "-W", "1", "1.1.1.1"], text=True, stderr=subprocess.DEVNULL)
            diag["internet_ok"] = True
            for line in out.splitlines():
                if "time=" in line:
                    part = line.split("time=")[1].split()[0]
                    diag["latency"] = float(part)
                    break
        except Exception:
            diag["internet_ok"] = False

    return {
        "ethernet": eth_devices,
        "vpn": vpn_conns,
        "saved": saved_conns,
        "details": ip_details,
        "diag": diag
    }

if __name__ == "__main__":
    do_ping = "--ping" in sys.argv
    print(json.dumps(get_net_info(do_ping)))
