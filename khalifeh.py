#!/usr/bin/env python3
"""
Khalifeh Tunnel - Simple & Fast TCP Tunnel
For bypassing network restrictions between IR and EU servers
"""

import os
import sys
import time
import socket
import struct
import threading
import subprocess
import re
from queue import Queue, Empty
from typing import Optional

# ========== تنظیمات ==========
DIAL_TIMEOUT = 5
KEEPALIVE_SECS = 20
SOCKBUF = 8 * 1024 * 1024
BUF_COPY = 256 * 1024
POOL_WAIT = 5
SYNC_INTERVAL = 3

# ========== توابع کمکی ==========

def log(msg: str, level: str = "INFO"):
    """لاگ ساده با زمان"""
    t = time.strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{t}] [{level}] {msg}", flush=True)

def tune_tcp(sock: socket.socket):
    """بهینه‌سازی سوکت TCP"""
    try:
        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, SOCKBUF)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, SOCKBUF)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
        if hasattr(socket, "TCP_KEEPIDLE"):
            sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_KEEPIDLE, KEEPALIVE_SECS)
            sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_KEEPINTVL, KEEPALIVE_SECS)
            sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_KEEPCNT, 3)
    except Exception:
        pass

def dial_tcp(host: str, port: int) -> socket.socket:
    """اتصال TCP به هاست و پورت مشخص"""
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    tune_tcp(s)
    s.settimeout(DIAL_TIMEOUT)
    s.connect((host, port))
    s.settimeout(None)
    return s

def recv_exact(sock: socket.socket, n: int) -> Optional[bytes]:
    """دریافت دقیقاً n بایت"""
    data = bytearray()
    while len(data) < n:
        chunk = sock.recv(n - len(data))
        if not chunk:
            return None
        data.extend(chunk)
    return bytes(data)

def pipe(a: socket.socket, b: socket.socket):
    """انتقال داده بین دو سوکت"""
    buf = bytearray(BUF_COPY)
    try:
        while True:
            n = a.recv_into(buf)
            if n <= 0:
                break
            b.sendall(memoryview(buf)[:n])
    except Exception:
        pass
    finally:
        try:
            a.shutdown(socket.SHUT_RD)
            b.shutdown(socket.SHUT_WR)
        except Exception:
            pass

def bridge(a: socket.socket, b: socket.socket):
    """پل دوطرفه بین دو سوکت"""
    t1 = threading.Thread(target=pipe, args=(a, b), daemon=True)
    t2 = threading.Thread(target=pipe, args=(b, a), daemon=True)
    t1.start()
    t2.start()
    t1.join()
    t2.join()
    try:
        a.close()
        b.close()
    except Exception:
        pass

# ========== حالت خارج (EU / Client) ==========

def get_listen_ports(exclude_bridge: int, exclude_sync: int) -> list:
    """دریافت لیست پورت‌های در حال شنیدن روی سیستم"""
    try:
        out = subprocess.check_output(
            ["ss", "-lntp"],
            stderr=subprocess.DEVNULL
        ).decode()
    except Exception:
        return []

    ports = set()
    for line in out.splitlines():
        parts = line.split()
        for part in parts:
            match = re.search(r':(\d+)$', part)
            if match:
                p = int(match.group(1))
                if p not in (exclude_bridge, exclude_sync) and 1 <= p <= 65535:
                    ports.add(p)
    return sorted(ports)

def eu_mode(iran_ip: str, bridge_port: int, sync_port: int, pool_size: int):
    """حالت کلاینت (خارج) - اتصال به سرور ایران"""
    log(f"خلیفه تانل - حالت خارج | ایران: {iran_ip}:{bridge_port} | Pool: {pool_size}")

    def sync_loop():
        """همگام‌سازی پورت‌ها با سرور"""
        while True:
            try:
                conn = dial_tcp(iran_ip, sync_port)
                log(f"متصل به سرور همگام‌سازی: {sync_port}")

                while True:
                    ports = get_listen_ports(bridge_port, sync_port)[:255]
                    payload = bytes([len(ports)])
                    for p in ports:
                        payload += struct.pack("!H", p)

                    conn.settimeout(2)
                    conn.sendall(payload)
                    conn.settimeout(None)
                    time.sleep(SYNC_INTERVAL)

            except Exception as e:
                log(f"خطا در همگام‌سازی: {e}", "ERROR")
                try:
                    conn.close()
                except Exception:
                    pass
                time.sleep(SYNC_INTERVAL)

    def worker():
        """کارگرهای پل معکوس"""
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
                log(f"پل زدن به پورت محلی: {target_port}")
                bridge(conn, local)
                delay = 0.2
            except Exception as e:
                time.sleep(delay)
                delay = min(delay * 2, 5.0)

    threading.Thread(target=sync_loop, daemon=True).start()
    for _ in range(pool_size):
        threading.Thread(target=worker, daemon=True).start()

    log("سیستم خارج فعال شد. در حال انتظار...")
    while True:
        time.sleep(3600)

# ========== حالت ایران (IR / Server) ==========

def ir_mode(bridge_port: int, sync_port: int, pool_size: int, auto_sync: bool, manual_ports: list):
    """حالت سرور (ایران)"""
    log(f"خلیفه تانل - حالت ایران | Bridge: {bridge_port} | Sync: {sync_port} | Pool: {pool_size}")

    pool = Queue(maxsize=pool_size * 2)
    active_ports = {}
    active_lock = threading.Lock()

    def bridge_listener():
        """پذیرش اتصالات از کلاینت خارج"""
        srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        srv.bind(("0.0.0.0", bridge_port))
        srv.listen(16384)
        log(f"پل بریج فعال شد: {bridge_port}")

        while True:
            try:
                conn, addr = srv.accept()
                tune_tcp(conn)
                pool.put(conn, block=False)
            except Exception as e:
                log(f"خطا در پل بریج: {e}", "ERROR")
                time.sleep(0.2)

    def handle_user(user_sock: socket.socket, target_port: int):
        """مدیریت اتصال کاربر به پورت هدف"""
        tune_tcp(user_sock)
        deadline = time.time() + POOL_WAIT
        eu_conn = None

        while time.time() < deadline:
            try:
                cand = pool.get(timeout=max(0.1, deadline - time.time()))
                cand.setblocking(False)
                try:
                    cand.recv(1, socket.MSG_PEEK)
                except BlockingIOError:
                    pass
                except Exception:
                    cand.close()
                    continue
                finally:
                    cand.setblocking(True)
                eu_conn = cand
                break
            except Empty:
                continue

        if eu_conn is None:
            user_sock.close()
            return

        try:
            eu_conn.settimeout(2)
            eu_conn.sendall(struct.pack("!H", target_port))
            eu_conn.settimeout(None)
            bridge(user_sock, eu_conn)
        except Exception as e:
            try:
                user_sock.close()
                eu_conn.close()
            except Exception:
                pass

    def open_port(port: int):
        """باز کردن یک پورت و شنیدن روی آن"""
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
            log(f"نمی‌توان پورت {port} را باز کرد: {e}", "ERROR")
            return

        log(f"پورت {port} باز شد ✅")

        def accept_users():
            while active_ports.get(port, False):
                try:
                    user, _ = srv.accept()
                    threading.Thread(target=handle_user, args=(user, port), daemon=True).start()
                except Exception as e:
                    if active_ports.get(port, False):
                        log(f"خطا در پورت {port}: {e}", "ERROR")
                    time.sleep(0.2)

        threading.Thread(target=accept_users, daemon=True).start()

    def sync_listener():
        """پذیرش اتصالات همگام‌سازی از کلاینت خارج"""
        srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        srv.bind(("0.0.0.0", sync_port))
        srv.listen(1024)
        log(f"همگام‌سازی فعال شد: {sync_port}")

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
                    except Exception:
                        pass
                    finally:
                        try:
                            c.close()
                        except Exception:
                            pass

                threading.Thread(target=handle_sync, args=(conn,), daemon=True).start()
            except Exception as e:
                log(f"خطا در همگام‌سازی: {e}", "ERROR")
                time.sleep(0.2)

    threading.Thread(target=bridge_listener, daemon=True).start()

    if auto_sync:
        threading.Thread(target=sync_listener, daemon=True).start()
    else:
        for p in manual_ports:
            open_port(p)
        log(f"پورت‌های دستی باز شدند: {manual_ports}")

    log("سیستم ایران فعال شد. در حال انتظار...")
    while True:
        time.sleep(3600)

# ========== محاسبه اندازه پول ==========

def auto_pool_size(role: str = "ir") -> int:
    """محاسبه خودکار اندازه پول بر اساس منابع سیستم"""
    try:
        import resource
        soft, _ = resource.getrlimit(resource.RLIMIT_NOFILE)
        nofile = soft if soft > 0 else 1024
    except Exception:
        nofile = 1024

    mem_mb = 0
    try:
        with open("/proc/meminfo", "r") as f:
            for line in f:
                if line.startswith("MemTotal:"):
                    mem_kb = int(line.split()[1])
                    mem_mb = mem_kb // 1024
                    break
    except Exception:
        mem_mb = 0

    reserve = 300
    fd_budget = max(0, nofile - reserve)
    frac = 0.22 if role == "ir" else 0.30
    fd_based = int(fd_budget * frac)
    ram_based = int((mem_mb / 1024) * 200) if mem_mb else 300

    pool = min(fd_based, ram_based)
    pool = max(50, min(pool, 1500))
    return pool

# ========== منوی اصلی ==========

def main():
    print("\n" + "="*50)
    print("    خلیفه تانل - Khalifeh Tunnel v1.0")
    print("    ابزار عبور از محدودیت‌های شبکه")
    print("="*50 + "\n")

    print("1) حالت سرور (ایران) - Server Mode")
    print("2) حالت کلاینت (خارج) - Client Mode")
    print("-"*50)

    choice = input("انتخاب کنید (1/2): ").strip()

    if choice == "1":
        print("\n--- تنظیمات سرور (ایران) ---")
        bridge = int(input("پورت بریج [7000]: ") or "7000")
        sync = int(input("پورت همگام‌سازی [7001]: ") or "7001")
        auto = input("همگام‌سازی خودکار؟ (y/n) [y]: ").strip().lower()

        if auto == "n":
            ports_str = input("پورت‌های دستی (مثال: 80,443,2083): ")
            manual = [int(p.strip()) for p in ports_str.split(",") if p.strip().isdigit()]
            pool = auto_pool_size("ir")
            ir_mode(bridge, sync, pool, False, manual)
        else:
            pool = auto_pool_size("ir")
            ir_mode(bridge, sync, pool, True, [])

    elif choice == "2":
        print("\n--- تنظیمات کلاینت (خارج) ---")
        iran_ip = input("آیپی سرور ایران: ").strip()
        bridge = int(input("پورت بریج [7000]: ") or "7000")
        sync = int(input("پورت همگام‌سازی [7001]: ") or "7001")
        pool = auto_pool_size("eu")
        eu_mode(iran_ip, bridge, sync, pool)

    else:
        print("انتخاب نامعتبر!")
        sys.exit(1)

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\nخروج از برنامه...")
        sys.exit(0)
    except Exception as e:
        log(f"خطای غیرمنتظره: {e}", "ERROR")
        sys.exit(1)