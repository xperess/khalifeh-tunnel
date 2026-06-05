#!/bin/bash
set -e
echo "========================================="
echo "Khalifeh Tunnel Installer"
echo "========================================="

if [[ "$EUID" -ne 0 ]]; then
    echo "Please run as root: sudo bash install.sh"
    exit 1
fi

mkdir -p /opt/khalifeh
mkdir -p /opt/khalifeh/profiles

cat > /opt/khalifeh/khalifeh.py << 'EOF'
#!/usr/bin/env python3
import sys, time, socket, struct, threading, subprocess, re
from queue import Queue, Empty

# Config
DIAL_TIMEOUT = 5
SOCKBUF = 8*1024*1024
BUF_COPY = 256*1024
POOL_WAIT = 5
SYNC_INTERVAL = 3

def log(msg, level="INFO"):
    t = time.strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{t}] {msg}")

def tune_tcp(s):
    try:
        s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, SOCKBUF)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, SOCKBUF)
    except: pass

def dial_tcp(host, port):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    tune_tcp(s)
    s.settimeout(5)
    s.connect((host, port))
    s.settimeout(None)
    return s

def recv_exact(sock, n):
    data = bytearray()
    while len(data) < n:
        chunk = sock.recv(n - len(data))
        if not chunk: return None
        data.extend(chunk)
    return bytes(data)

def pipe(a, b):
    buf = bytearray(BUF_COPY)
    try:
        while True:
            n = a.recv_into(buf)
            if n <= 0: break
            b.sendall(memoryview(buf)[:n])
    except: pass
    finally:
        try: a.shutdown(socket.SHUT_RD)
        except: pass
        try: b.shutdown(socket.SHUT_WR)
        except: pass

def bridge(a, b):
    t1 = threading.Thread(target=pipe, args=(a,b), daemon=True)
    t2 = threading.Thread(target=pipe, args=(b,a), daemon=True)
    t1.start(); t2.start()
    t1.join(); t2.join()
    try: a.close(); b.close()
    except: pass

def get_exclude_ports():
    try:
        with open("/opt/khalifeh/exclude.txt", "r") as f:
            return set([int(x.strip()) for x in f.read().split(",") if x.strip().isdigit()])
    except:
        return {22,53,80,443,2096,9876,11111}

def get_listen_ports(exclude_bridge, exclude_sync):
    exclude = get_exclude_ports().union({exclude_bridge, exclude_sync})
    try:
        out = subprocess.check_output(["ss","-lntp"], stderr=subprocess.DEVNULL).decode()
    except:
        return []
    ports = set()
    for line in out.splitlines():
        m = re.search(r':(\d+)$', line)
        if m:
            p = int(m.group(1))
            if p not in exclude and 1 <= p <= 65535:
                ports.add(p)
    return sorted(ports)

def eu_mode(ip, bridge, sync, pool):
    log(f"EU Mode | Iran: {ip}:{bridge}")
    def sync_loop():
        while True:
            try:
                conn = dial_tcp(ip, sync)
                while True:
                    ports = get_listen_ports(bridge, sync)[:255]
                    payload = bytes([len(ports)])
                    for p in ports:
                        payload += struct.pack("!H", p)
                    conn.sendall(payload)
                    time.sleep(SYNC_INTERVAL)
            except Exception as e:
                log(f"Sync error: {e}")
                time.sleep(SYNC_INTERVAL)
    def worker():
        delay = 0.2
        while True:
            try:
                conn = dial_tcp(ip, bridge)
                hdr = recv_exact(conn, 2)
                if not hdr: continue
                port = struct.unpack("!H", hdr)[0]
                local = dial_tcp("127.0.0.1", port)
                bridge(conn, local)
                delay = 0.2
            except:
                time.sleep(delay)
                delay = min(delay*2, 5.0)
    threading.Thread(target=sync_loop, daemon=True).start()
    for _ in range(pool):
        threading.Thread(target=worker, daemon=True).start()
    while True: time.sleep(3600)

def ir_mode(bridge, sync, pool, auto_sync, manual_ports):
    log(f"IR Mode | Bridge: {bridge} | Sync: {sync}")
    pool_queue = Queue(maxsize=pool*2)
    active = {}
    lock = threading.Lock()
    exclude = get_exclude_ports()
    def bridge_listener():
        srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        srv.bind(("0.0.0.0", bridge))
        srv.listen(10000)
        while True:
            try:
                conn, _ = srv.accept()
                tune_tcp(conn)
                pool_queue.put(conn, block=False)
            except: time.sleep(0.2)
    def handle_user(sock, port):
        tune_tcp(sock)
        deadline = time.time() + POOL_WAIT
        eu = None
        while time.time() < deadline:
            try:
                eu = pool_queue.get(timeout=max(0.1, deadline - time.time()))
                break
            except Empty: continue
        if eu is None:
            sock.close()
            return
        try:
            eu.sendall(struct.pack("!H", port))
            bridge(sock, eu)
        except:
            try: sock.close(); eu.close()
            except: pass
    def open_port(p):
        if p in exclude: return
        with lock:
            if p in active: return
            active[p] = True
        try:
            srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            srv.bind(("0.0.0.0", p))
            srv.listen(10000)
        except:
            with lock: active.pop(p, None)
            return
        log(f"Port {p} opened")
        def accept_users():
            while active.get(p, False):
                try:
                    user, _ = srv.accept()
                    threading.Thread(target=handle_user, args=(user,p), daemon=True).start()
                except: time.sleep(0.2)
        threading.Thread(target=accept_users, daemon=True).start()
    def sync_listener():
        srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        srv.bind(("0.0.0.0", sync))
        srv.listen(1000)
        while True:
            try:
                conn, _ = srv.accept()
                def handle(c):
                    try:
                        while True:
                            h = recv_exact(c, 1)
                            if not h: break
                            count = h[0]
                            for _ in range(count):
                                pd = recv_exact(c, 2)
                                if not pd: return
                                open_port(struct.unpack("!H", pd)[0])
                    except: pass
                    finally: c.close()
                threading.Thread(target=handle, args=(conn,), daemon=True).start()
            except: time.sleep(0.2)
    threading.Thread(target=bridge_listener, daemon=True).start()
    if auto_sync:
        threading.Thread(target=sync_listener, daemon=True).start()
    else:
        for p in manual_ports:
            open_port(p)
    while True: time.sleep(3600)

def main():
    print("\nKhalifeh Tunnel v2.0")
    print("1) Server (Iran)")
    print("2) Client (EU)")
    choice = input("Choose: ").strip()
    if choice == "1":
        bridge = int(input("Bridge port [7000]: ") or "7000")
        sync = int(input("Sync port [7001]: ") or "7001")
        auto = input("Auto sync? (y/n) [y]: ").strip().lower()
        if auto == "n":
            ports = [int(p) for p in input("Ports (comma): ").split(",") if p.strip().isdigit()]
            ir_mode(bridge, sync, 300, False, ports)
        else:
            ir_mode(bridge, sync, 300, True, [])
    else:
        ip = input("Iran IP: ").strip()
        bridge = int(input("Bridge port [7000]: ") or "7000")
        sync = int(input("Sync port [7001]: ") or "7001")
        eu_mode(ip, bridge, sync, 300)

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nExiting")
        sys.exit(0)
EOF

cat > /opt/khalifeh/manager.sh << 'EOF'
#!/bin/bash
BASE="/opt/khalifeh"
PROFILES="$BASE/profiles"

mkdir -p $PROFILES

# Load saved profile if exists
if [ -f "$BASE/current_profile" ]; then
    source "$BASE/current_profile"
fi

while true; do
    clear
    echo ""
    echo "========================================="
    echo "   Khalifeh Tunnel Manager"
    echo "========================================="
    echo ""
    echo "1) Create/Edit Profile"
    echo "2) Start Tunnel"
    echo "3) Stop Tunnel"
    echo "4) View Logs"
    echo "5) Manage Excluded Ports"
    echo "6) Uninstall (Complete Removal)"
    echo "7) Exit"
    echo ""
    read -p "Choose: " ch

    case $ch in
        1)
            echo ""
            read -p "Profile name: " name
            mkdir -p $PROFILES/$name
            echo ""
            echo "Mode:"
            echo "1) Server (Iran)"
            echo "2) Client (EU)"
            read -p "Choose: " mode
            if [ "$mode" == "1" ]; then
                read -p "Bridge port [7000]: " bridge
                bridge=${bridge:-7000}
                read -p "Sync port [7001]: " sync
                sync=${sync:-7001}
                read -p "Auto sync? (y/n) [y]: " auto
                auto=${auto:-y}
                if [ "$auto" == "n" ]; then
                    read -p "Ports (comma): " ports
                else
                    ports=""
                fi
                echo "mode=server" > $PROFILES/$name/config
                echo "bridge=$bridge" >> $PROFILES/$name/config
                echo "sync=$sync" >> $PROFILES/$name/config
                echo "auto=$auto" >> $PROFILES/$name/config
                echo "ports=$ports" >> $PROFILES/$name/config
                echo "CURRENT_PROFILE=$name" > $BASE/current_profile
            else
                read -p "Iran IP: " ip
                read -p "Bridge port [7000]: " bridge
                bridge=${bridge:-7000}
                read -p "Sync port [7001]: " sync
                sync=${sync:-7001}
                echo "mode=client" > $PROFILES/$name/config
                echo "ip=$ip" >> $PROFILES/$name/config
                echo "bridge=$bridge" >> $PROFILES/$name/config
                echo "sync=$sync" >> $PROFILES/$name/config
                echo "CURRENT_PROFILE=$name" > $BASE/current_profile
            fi
            echo "Profile saved!"
            sleep 1
            ;;
        2)
            if [ ! -f "$BASE/current_profile" ]; then
                echo "No profile. Create one first."
                sleep 2
                continue
            fi
            source $BASE/current_profile
            source $PROFILES/$CURRENT_PROFILE/config
            pkill -f khalifeh.py 2>/dev/null
            sleep 1
            if [ "$mode" == "server" ]; then
                if [ "$auto" == "n" ]; then
                    echo "$ports" | python3 $BASE/khalifeh.py --mode server --bridge $bridge --sync $sync --manual
                else
                    python3 $BASE/khalifeh.py --mode server --bridge $bridge --sync $sync &
                fi
            else
                python3 $BASE/khalifeh.py --mode client --ip $ip --bridge $bridge --sync $sync &
            fi
            echo "Tunnel started!"
            sleep 2
            ;;
        3)
            pkill -f khalifeh.py
            echo "Tunnel stopped"
            sleep 1
            ;;
        4)
            pkill -f khalifeh.py 2>/dev/null
            echo "Starting tunnel with logs..."
            source $BASE/current_profile 2>/dev/null
            if [ -f "$PROFILES/$CURRENT_PROFILE/config" ]; then
                source $PROFILES/$CURRENT_PROFILE/config
                if [ "$mode" == "server" ]; then
                    if [ "$auto" == "n" ]; then
                        echo "$ports" | python3 $BASE/khalifeh.py --mode server --bridge $bridge --sync $sync --manual
                    else
                        python3 $BASE/khalifeh.py --mode server --bridge $bridge --sync $sync
                    fi
                else
                    python3 $BASE/khalifeh.py --mode client --ip $ip --bridge $bridge --sync $sync
                fi
            else
                python3 $BASE/khalifeh.py
            fi
            ;;
        5)
            echo ""
            echo "Current excluded ports:"
            if [ -f "$BASE/exclude.txt" ]; then
                cat $BASE/exclude.txt
            else
                echo "22,53,80,443,2096,9876,11111"
            fi
            echo ""
            echo "1) Add port"
            echo "2) Remove port"
            read -p "Choose: " excl
            if [ "$excl" == "1" ]; then
                read -p "Port to add: " p
                if [ -f "$BASE/exclude.txt" ]; then
                    curr=$(cat $BASE/exclude.txt)
                    echo "$curr,$p" > $BASE/exclude.txt
                else
                    echo "22,53,80,443,2096,9876,11111,$p" > $BASE/exclude.txt
                fi
            elif [ "$excl" == "2" ]; then
                read -p "Port to remove: " p
                if [ -f "$BASE/exclude.txt" ]; then
                    sed -i "s/,$p//g; s/$p,//g; s/$p//g" $BASE/exclude.txt
                fi
            fi
            echo "Done"
            sleep 1
            ;;
        6)
            echo ""
            read -p "Complete uninstall? (y/n): " confirm
            if [ "$confirm" == "y" ]; then
                pkill -f khalifeh.py 2>/dev/null
                rm -rf /opt/khalifeh
                rm -f /usr/local/bin/khalifeh
                echo "Khalifeh Tunnel completely removed!"
                exit 0
            fi
            ;;
        7)
            exit 0
            ;;
    esac
done
EOF

chmod +x /opt/khalifeh/khalifeh.py
chmod +x /opt/khalifeh/manager.sh
ln -sf /opt/khalifeh/manager.sh /usr/local/bin/khalifeh

apt-get update -y >/dev/null 2>&1
apt-get install -y python3 screen >/dev/null 2>&1

echo ""
echo "========================================="
echo "Installation Complete!"
echo "========================================="
echo ""
echo "Run: sudo khalifeh"
echo ""