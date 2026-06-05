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
import json
from queue import Queue, Empty
from typing import Optional

# ========== تنظیمات ==========
CONFIG_FILE = "/opt/khalifeh/config.json"
DIAL_TIMEOUT = 5
KEEPALIVE_SECS = 20
SOCKBUF = 8 * 1024 * 1024
BUF_COPY = 256 * 1024
POOL_WAIT = 5
SYNC_INTERVAL = 3

# پورت‌های پیش‌فرض ممنوع
DEFAULT_EXCLUDE_PORTS = {22, 53, 80, 443, 2096, 9876, 11111}
EXCLUDE_PORTS = set(DEFAULT_EXCLUDE_PORTS)

# ========== توابع کمکی ==========

def load_config():
    """بارگذاری تنظیمات از فایل"""
    global EXCLUDE_PORTS
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, 'r') as f:
                config = json.load(f)
                if 'exclude_ports' in config:
                    EXCLUDE_PORTS = set(config['exclude_ports'])
        except:
            pass

def save_config():
    """ذخیره تنظیمات در فایل"""
    config = {'exclude_ports': list(EXCLUDE_PORTS)}
    with open(CONFIG_FILE, 'w') as f:
        json.dump(config, f, indent=2)

def log(msg: str, level: str = "INFO"):
    """لاگ ساده با زمان"""
    t = time.strftime("%Y-%m-%d %H:%M:%S")
    
    symbols = {
        "INFO": "ℹ",
        "ERROR": "✖",
        "WARN": "⚠",
        "OK": "✓",
    }
    sym = symbols.get(level, "•")
    
    if level == "ERROR":
        print(f"[{t}] [{sym}] {msg}", flush=True)
    elif level == "OK":
        print(f"[{t}] [{sym}] {msg}", flush=True)
    else:
        print(f"[{t}] [{sym}] {msg}", flush=True)

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
    exclude = EXCLUDE_PORTS.union({exclude_bridge, exclude_sync})
    
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
                if p not in exclude and 1 <= p <= 65535:
                    ports.add(p)
    return sorted(ports)

def eu_mode(iran_ip: str, bridge_port: int, sync_port: int, pool_size: int):
    """حالت کلاینت (خارج) - اتصال به سرور ایران"""
    log(f"خلیفه تانل - حالت خارج | ایران: {iran_ip}:{bridge_port} | Pool: {pool_size}", "OK")
    
    def sync_loop():
        """همگام‌سازی پورت‌ها با سرور"""
        while True:
            try:
                conn = dial_tcp(iran_ip, sync_port)
                log(f"متصل به سرور همگام‌سازی: {sync_port}", "OK")
                
                while True:
                    ports = get_listen_ports(bridge_port, sync_port)[:255]
                    log(f"ارسال {len(ports)} پورت به سرور ایران", "INFO")
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
                log(f"پل زدن به پورت محلی: {target_port}", "OK")
                bridge(conn, local)
                delay = 0.2
            except Exception as e:
                time.sleep(delay)
                delay = min(delay * 2, 5.0)
    
    threading.Thread(target=sync_loop, daemon=True).start()
    for _ in range(pool_size):
        threading.Thread(target=worker, daemon=True).start()
    
    log("سیستم خارج فعال شد. در حال انتظار...", "OK")
    while True:
        time.sleep(3600)

# ========== حالت ایران (IR / Server) ==========

def ir_mode(bridge_port: int, sync_port: int, pool_size: int, auto_sync: bool, manual_ports: list):
    """حالت سرور (ایران)"""
    log(f"خلیفه تانل - حالت ایران | Bridge: {bridge_port} | Sync: {sync_port} | Pool: {pool_size}", "OK")
    
    pool = Queue(maxsize=pool_size * 2)
    active_ports = {}
    active_lock = threading.Lock()
    
    def bridge_listener():
        """پذیرش اتصالات از کلاینت خارج"""
        srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        srv.bind(("0.0.0.0", bridge_port))
        srv.listen(16384)
        log(f"پل بریج فعال شد: {bridge_port}", "OK")
        
        while True:
            try:
                conn, addr = srv.accept()
                log(f"اتصال جدید از خارج: {addr[0]}:{addr[1]}")
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
                if cand.fileno() == -1:
                    continue
                eu_conn = cand
                break
            except Empty:
                continue
        
        if eu_conn is None:
            log(f"هیچ اتصالی به خارج برای پورت {target_port} موجود نیست", "WARN")
            user_sock.close()
            return
        
        try:
            eu_conn.settimeout(2)
            eu_conn.sendall(struct.pack("!H", target_port))
            eu_conn.settimeout(None)
            bridge(user_sock, eu_conn)
        except Exception as e:
            log(f"خطا در پل زدن پورت {target_port}: {e}", "ERROR")
            try:
                user_sock.close()
                eu_conn.close()
            except Exception:
                pass
    
    def open_port(port: int):
        """باز کردن یک پورت و شنیدن روی آن"""
        if port in EXCLUDE_PORTS:
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
            if port not in EXCLUDE_PORTS:
                log(f"نمی‌توان پورت {port} را باز کرد: {e}", "WARN")
            return
        
        log(f"پورت {port} باز شد ✅", "OK")
        
        def accept_users():
            while active_ports.get(port, False):
                try:
                    user, addr = srv.accept()
                    log(f"اتصال جدید به پورت {port} از {addr[0]}:{addr[1]}")
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
        log(f"همگام‌سازی فعال شد: {sync_port}", "OK")
        
        while True:
            try:
                conn, addr = srv.accept()
                log(f"کلاینت همگام‌سازی متصل شد: {addr[0]}:{addr[1]}")
                
                def handle_sync(c):
                    try:
                        while True:
                            h = recv_exact(c, 1)
                            if not h:
                                break
                            count = h[0]
                            log(f"دریافت {count} پورت از کلاینت خارج", "INFO")
                            for _ in range(count):
                                pd = recv_exact(c, 2)
                                if not pd:
                                    return
                                p = struct.unpack("!H", pd)[0]
                                open_port(p)
                    except Exception as e:
                        log(f"خطا در همگام‌سازی: {e}", "ERROR")
                    finally:
                        try:
                            c.close()
                        except Exception:
                            pass
                
                threading.Thread(target=handle_sync, args=(conn,), daemon=True).start()
            except Exception as e:
                log(f"خطا در پذیرش همگام‌سازی: {e}", "ERROR")
                time.sleep(0.2)
    
    threading.Thread(target=bridge_listener, daemon=True).start()
    
    if auto_sync:
        threading.Thread(target=sync_listener, daemon=True).start()
    else:
        for p in manual_ports:
            open_port(p)
        log(f"پورت‌های دستی باز شدند: {manual_ports}", "OK")
    
    log("سیستم ایران فعال شد. در حال انتظار...", "OK")
    while True:
        time.sleep(3600)

def auto_pool_size(role: str = "ir") -> int:
    """محاسبه خودکار اندازه پول"""
    try:
        import resource
        soft, _ = resource.getrlimit(resource.RLIMIT_NOFILE)
        nofile = soft if soft > 0 else 1024
    except Exception:
        nofile = 1024
    
    reserve = 300
    fd_budget = max(0, nofile - reserve)
    frac = 0.22 if role == "ir" else 0.30
    fd_based = int(fd_budget * frac)
    
    pool = max(30, min(fd_based, 500))
    return pool

def manage_exclude_ports():
    """مدیریت پورت‌های ممنوع"""
    global EXCLUDE_PORTS
    load_config()
    
    while True:
        print("\n" + "="*50)
        print("    مدیریت پورت‌های حذف شده از تانل")
        print("="*50)
        print(f"\nپورت‌های فعلی: {sorted(EXCLUDE_PORTS)}")
        print("\n1) اضافه کردن پورت")
        print("2) حذف پورت از لیست")
        print("3) بازگشت")
        
        choice = input("\nانتخاب کنید: ").strip()
        
        if choice == "1":
            port = input("پورت را وارد کنید: ").strip()
            if port.isdigit():
                EXCLUDE_PORTS.add(int(port))
                save_config()
                print(f"✅ پورت {port} به لیست ممنوعه اضافه شد")
            else:
                print("❌ پورت نامعتبر")
        
        elif choice == "2":
            port = input("پورت را وارد کنید: ").strip()
            if port.isdigit() and int(port) in EXCLUDE_PORTS:
                EXCLUDE_PORTS.remove(int(port))
                save_config()
                print(f"✅ پورت {port} از لیست ممنوعه حذف شد")
            else:
                print("❌ پورت در لیست نیست")
        
        elif choice == "3":
            break
        
        input("\nEnter to continue...")

def print_banner():
    """نمایش بنر ساده"""
    print("\n" + "="*50)
    print("   خلیفه تانل - Khalifeh Tunnel v2.0")
    print("   ابزار عبور از محدودیت‌های شبکه")
    print("="*50 + "\n")

def main():
    load_config()
    
    print_banner()
    
    print("1) حالت سرور (ایران) - Server Mode")
    print("2) حالت کلاینت (خارج) - Client Mode")
    print("3) مدیریت پورت‌های حذف شده")
    print("-"*50)
    
    choice = input("انتخاب کنید (1/2/3): ").strip()
    
    if choice == "1":
        print("\n--- تنظیمات سرور (ایران) ---")
        bridge = int(input("پورت بریج [7000]: ") or "7000")
        sync = int(input("پورت همگام‌سازی [7001]: ") or "7001")
        auto = input("همگام‌سازی خودکار؟ (y/n) [y]: ").strip().lower()
        
        print(f"\nپورت‌های حذف شده از تانل: {sorted(EXCLUDE_PORTS)}")
        
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
    
    elif choice == "3":
        manage_exclude_ports()
        main()
    
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