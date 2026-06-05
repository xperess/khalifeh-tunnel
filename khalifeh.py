#!/usr/bin/env python3
"""
Khalifeh Tunnel - Main Core
"""

import os
import sys
import time
import socket
import struct
import threading
import subprocess
import re
import json
from queue import Queue, Empty
from typing import Optional

# Settings
DIAL_TIMEOUT = 5
KEEPALIVE_SECS = 20
SOCKBUF = 8 * 1024 * 1024
BUF_COPY = 256 * 1024
POOL_WAIT = 5
SYNC_INTERVAL = 3

def log(msg: str, level: str = "INFO"):
    t = time.strftime("%Y-%m-%d %H:%M:%S")
    symbols = {"INFO": "i", "ERROR": "x", "WARN": "!", "OK": "+"}
    sym = symbols.get(level, ".")
    print(f"[{t}] [{sym}] {msg}", flush=True)

def tune_tcp(sock):
    try:
        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, SOCKBUF)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, SOCKBUF)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
    except:
        pass

def dial_tcp(host, port):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    tune_tcp(s)
    s.settimeout(DIAL_TIMEOUT)
    s.connect((host, port))
    s.settimeout(None)
    return s

def recv_exact(sock, n):
    data = bytearray()
    while len(data) < n:
        chunk = sock.recv(n - len(data))
        if not chunk:
            return None
        data.extend(chunk)
    return bytes(data)

def pipe(a, b):
    buf = bytearray(BUF_COPY)
    try:
        while True:
            n = a.recv_into(buf)
            if n <= 0:
                break
            b.sendall(memoryview(buf)[:n])
    except:
        pass
    finally:
        try:
            a.shutdown(socket.SHUT_RD)
            b.shutdown(socket.SHUT_WR)
        except:
            pass

def bridge(a, b):
    t1 = threading.Thread(target=pipe, args=(a, b), daemon=True)
    t2 = threading.Thread(target=pipe, args=(b, a), daemon=True)
    t1.start()
    t2.start()
    t1.join()
    t2.join()
    try:
        a.close()
        b.close()
    except:
        pass

def get_exclude_ports():
    exclude_file = "/opt/khalifeh/exclude_ports.txt"
    if os.path.exists(exclude_file):
        with open(exclude_file, 'r') as f:
            content = f.read().strip()
            return set([int(p) for p in content.split(',') if p.strip().isdigit()])
    return {22, 53, 80, 443, 2096, 9876, 11111}

def get_listen_ports(exclude_bridge, exclude_sync):
    exclude = get_exclude_ports().union({exclude_bridge, exclude_sync})
    try:
        out = subprocess.check_output(["ss", "-lntp"], stderr=subprocess.DEVNULL).decode()
    except:
        return []
    ports = set()
    for line in out.splitlines():
        match = re.search(r':(\d+)$', line)
        if match:
            p = int(match.group(1))
            if p not in exclude and 1 <= p <= 65535:
                ports.add(p)
    return sorted(ports)

def eu_mode(iran_ip, bridge_port, sync_port, pool_size):
    log(f"EU Mode | Iran: {iran_ip}:{bridge_port} | Pool: {pool_size}", "OK")
    
    def sync_loop():
        while True:
            try:
                conn = dial_tcp(iran_ip, sync_port)
                log(f"Connected to sync server: {sync_port}", "OK")
                while True:
                    ports = get_listen_ports(bridge_port, sync_port)[:255]
                    payload = bytes([len(ports)])
                    for p in ports:
                        payload += struct.pack("!H", p)
                    conn.sendall(payload)
                    time.sleep(SYNC_INTERVAL)
            except Exception as e:
                log(f"Sync error: {e}", "ERROR")
                time.sleep(SYNC_INTERVAL)
    
    def worker():
        delay = 0.2
        while True:
            try:
                conn = dial_tcp(iran_ip, bridge_port)
                hdr = recv_exact(conn, 2)
                if not hdr:
                    conn.close()
                    continue
                target_port = struct.unpack("!H", hdr)[0]
                local = dial_tcp("127.0.0.1", target_port)
                bridge(conn, local)
                delay = 0.2
            except:
                time.sleep(delay)
                delay = min(delay * 2, 5.0)
    
    threading.Thread(target=sync_loop, daemon=True).start()
    for _ in range(pool_size):
        threading.Thread(target=worker, daemon=True).start()
    
    log("EU system active. Waiting...", "OK")
    while True:
        time.sleep(3600)

def ir_mode(bridge_port, sync_port, pool_size, auto_sync, manual_ports):
    log(f"IR Mode | Bridge: {bridge_port} | Sync: {sync_port} | Pool: {pool_size}", "OK")
    
    pool = Queue(maxsize=pool_size * 2)
    active_ports = {}
    active_lock = threading.Lock()
    exclude_ports = get_exclude_ports()
    
    def bridge_listener():
        srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        srv.bind(("0.0.0.0", bridge_port))
        srv.listen(16384)
        log(f"Bridge listening on {bridge_port}", "OK")
        while True:
            try:
                conn, addr = srv.accept()
                tune_tcp(conn)
                pool.put(conn, block=False)
            except:
                time.sleep(0.2)
    
    def handle_user(user_sock, target_port):
        tune_tcp(user_sock)
        deadline = time.time() + POOL_WAIT
        eu_conn = None
        while time.time() < deadline:
            try:
                cand = pool.get(timeout=max(0.1, deadline - time.time()))
                eu_conn = cand
                break
            except Empty:
                continue
        if eu_conn is None:
            user_sock.close()
            return
        try:
            eu_conn.sendall(struct.pack("!H", target_port))
            bridge(user_sock, eu_conn)
        except:
            try:
                user_sock.close()
                eu_conn.close()
            except:
                pass
    
    def open_port(port):
        if port in exclude_ports:
            return
        with active_lock:
            if port in active_ports:
                return
            active_ports[port] = True
        try:
            srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            srv.bind(("0.0.0.0", port))
            srv.listen(16384)
        except Exception as e:
            with active_lock:
                active_ports.pop(port, None)
            return
        log(f"Port {port} opened", "OK")
        def accept_users():
            while active_ports.get(port, False):
                try:
                    user, _ = srv.accept()
                    threading.Thread(target=handle_user, args=(user, port), daemon=True).start()
                except:
                    time.sleep(0.2)
        threading.Thread(target=accept_users, daemon=True).start()
    
    def sync_listener():
        srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        srv.bind(("0.0.0.0", sync_port))
        srv.listen(1024)
        log(f"Sync listening on {sync_port}", "OK")
        while True:
            try:
                conn, _ = srv.accept()
                def handle_sync(c):
                    try:
                        while True:
                            h = recv_exact(c, 1)
                            if not h:
                                break
                            count = h[0]
                            for _ in range(count):
                                pd = recv_exact(c, 2)
                                if not pd:
                                    return
                                p = struct.unpack("!H", pd)[0]
                                open_port(p)
                    except:
                        pass
                    finally:
                        try:
                            c.close()
                        except:
                            pass
                threading.Thread(target=handle_sync, args=(conn,), daemon=True).start()
            except:
                time.sleep(0.2)
    
    threading.Thread(target=bridge_listener, daemon=True).start()
    if auto_sync:
        threading.Thread(target=sync_listener, daemon=True).start()
    else:
        for p in manual_ports:
            open_port(p)
        log(f"Manual ports: {manual_ports}", "OK")
    
    log("IR system active. Waiting...", "OK")
    while True:
        time.sleep(3600)

def auto_pool_size(role="ir"):
    try:
        import resource
        soft, _ = resource.getrlimit(resource.RLIMIT_NOFILE)
        nofile = soft if soft > 0 else 1024
    except:
        nofile = 1024
    reserve = 300
    fd_budget = max(0, nofile - reserve)
    frac = 0.22 if role == "ir" else 0.30
    pool = max(30, min(int(fd_budget * frac), 500))
    return pool

def main():
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--profile', help='Profile file')
    args = parser.parse_args()
    
    if args.profile and os.path.exists(args.profile):
        # Load from profile
        config = {}
        with open(args.profile, 'r') as f:
            for line in f:
                if '=' in line:
                    k, v = line.strip().split('=', 1)
                    config[k] = v
        
        mode = config.get('mode', 'server')
        bridge = int(config.get('bridge_port', 7000))
        sync = int(config.get('sync_port', 7001))
        pool = auto_pool_size(mode)
        
        if mode == 'client':
            iran_ip = config.get('iran_ip')
            if not iran_ip:
                log("Iran IP not set in profile", "ERROR")
                return
            eu_mode(iran_ip, bridge, sync, pool)
        else:
            auto_sync = config.get('auto_sync', 'y').lower() == 'y'
            ports_str = config.get('ports', '')
            manual_ports = [int(p) for p in ports_str.split(',') if p.strip().isdigit()] if ports_str else []
            ir_mode(bridge, sync, pool, auto_sync, manual_ports)
    else:
        # Interactive mode
        print("\nKhalifeh Tunnel v2.0")
        print("1) Server Mode (Iran)")
        print("2) Client Mode (EU)")
        choice = input("Choose (1/2): ").strip()
        
        if choice == "1":
            bridge = int(input("Bridge port [7000]: ") or "7000")
            sync = int(input("Sync port [7001]: ") or "7001")
            auto = input("Auto sync? (y/n) [y]: ").strip().lower()
            exclude = get_exclude_ports()
            print(f"Excluded ports: {sorted(exclude)}")
            if auto == "n":
                ports_str = input("Manual ports (comma separated): ")
                manual = [int(p) for p in ports_str.split(',') if p.strip().isdigit()]
                ir_mode(bridge, sync, auto_pool_size("ir"), False, manual)
            else:
                ir_mode(bridge, sync, auto_pool_size("ir"), True, [])
        else:
            iran_ip = input("Iran server IP: ").strip()
            bridge = int(input("Bridge port [7000]: ") or "7000")
            sync = int(input("Sync port [7001]: ") or "7001")
            eu_mode(iran_ip, bridge, sync, auto_pool_size("eu"))

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nExiting...")
        sys.exit(0)