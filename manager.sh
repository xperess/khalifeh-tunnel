#!/usr/bin/env bash
set -euo pipefail

# خلیفه تانل - مدیریت ساده

APP_NAME="Khalifeh Tunnel"
VERSION="1.0.0"
PYTHON_SCRIPT="/opt/khalifeh/khalifeh.py"
SERVICE_NAME="khalifeh"

# رنگ‌ها
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; NC=''
fi

need_root() {
    if [[ "$(id -u)" != "0" ]]; then
        echo -e "${RED}لطفاً با دسترسی روت اجرا کنید: sudo $0${NC}"
        exit 1
    fi
}

show_menu() {
    clear
    echo -e "${CYAN}================================${NC}"
    echo -e "${CYAN}    $APP_NAME v$VERSION${NC}"
    echo -e "${CYAN}================================${NC}"
    echo ""
    echo "1) نصب/بروزرسانی"
    echo "2) اجرای تونل (حالت تعاملی)"
    echo "3) اجرا به عنوان سرویس (systemd)"
    echo "4) توقف سرویس"
    echo "5) مشاهده لاگ‌ها"
    echo "6) حذف کامل"
    echo "0) خروج"
    echo ""
    read -p "انتخاب: " choice
}

install_tunnel() {
    echo -e "${GREEN}[*] نصب خلیفه تانل...${NC}"
    
    # ایجاد دایرکتوری
    mkdir -p /opt/khalifeh
    
    # کپی فایل اصلی
    if [[ -f "$0" ]] && [[ "$0" != "bash" ]]; then
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        cp "$SCRIPT_DIR/khalifeh.py" /opt/khalifeh/ 2>/dev/null || {
            echo -e "${RED}فایل khalifeh.py یافت نشد!${NC}"
            exit 1
        }
    else
        echo -e "${RED}لطفاً فایل khalifeh.py را در /opt/khalifeh/ قرار دهید${NC}"
        exit 1
    fi
    
    chmod +x /opt/khalifeh/khalifeh.py
    sed -i 's/\r$//' /opt/khalifeh/khalifeh.py
    
    # نصب وابستگی‌ها
    echo -e "${GREEN}[*] نصب وابستگی‌ها...${NC}"
    apt-get update -y >/dev/null 2>&1 || true
    apt-get install -y python3 screen iproute2 >/dev/null 2>&1
    
    echo -e "${GREEN}[✓] نصب کامل شد!${NC}"
    echo ""
    echo "اجرا با: sudo khalifeh-manager"
    
    # نصب به PATH
    ln -sf /opt/khalifeh/khalifeh.py /usr/local/bin/khalifeh-tunnel 2>/dev/null || true
    chmod +x /usr/local/bin/khalifeh-tunnel 2>/dev/null || true
    
    read -p "Enter to continue..."
}

run_interactive() {
    echo -e "${GREEN}[*] اجرای تونل...${NC}"
    python3 /opt/khalifeh/khalifeh.py
}

install_service() {
    echo -e "${GREEN}[*] نصب سرویس systemd...${NC}"
    
    cat > /etc/systemd/system/$SERVICE_NAME.service <<EOF
[Unit]
Description=Khalifeh Tunnel Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/khalifeh-tunnel
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable $SERVICE_NAME
    systemctl start $SERVICE_NAME
    
    echo -e "${GREEN}[✓] سرویس راه‌اندازی شد${NC}"
    echo -e "وضعیت: ${CYAN}systemctl status $SERVICE_NAME${NC}"
    read -p "Enter to continue..."
}

stop_service() {
    echo -e "${YELLOW}[*] توقف سرویس...${NC}"
    systemctl stop $SERVICE_NAME 2>/dev/null || true
    systemctl disable $SERVICE_NAME 2>/dev/null || true
    pkill -f "khalifeh.py" 2>/dev/null || true
    echo -e "${GREEN}[✓] تونل متوقف شد${NC}"
    read -p "Enter to continue..."
}

show_logs() {
    journalctl -u $SERVICE_NAME -f -n 50
}

uninstall() {
    echo -e "${RED}[!] حذف کامل خلیفه تانل...${NC}"
    read -p "آیا مطمئن هستید؟ (y/n): " confirm
    if [[ "$confirm" == "y" ]]; then
        systemctl stop $SERVICE_NAME 2>/dev/null || true
        systemctl disable $SERVICE_NAME 2>/dev/null || true
        rm -f /etc/systemd/system/$SERVICE_NAME.service
        rm -rf /opt/khalifeh
        rm -f /usr/local/bin/khalifeh-tunnel
        systemctl daemon-reload
        echo -e "${GREEN}[✓] حذف شد${NC}"
    fi
    read -p "Enter to continue..."
}

# ========== اصلی ==========
need_root

# نصب خودکار اگر فایل پایتون وجود نداشت
if [[ ! -f "/opt/khalifeh/khalifeh.py" ]] && [[ -f "$(dirname "${BASH_SOURCE[0]}")/khalifeh.py" ]]; then
    mkdir -p /opt/khalifeh
    cp "$(dirname "${BASH_SOURCE[0]}")/khalifeh.py" /opt/khalifeh/
    chmod +x /opt/khalifeh/khalifeh.py
    sed -i 's/\r$//' /opt/khalifeh/khalifeh.py
    ln -sf /opt/khalifeh/khalifeh.py /usr/local/bin/khalifeh-tunnel 2>/dev/null || true
fi

while true; do
    show_menu
    case $choice in
        1) install_tunnel ;;
        2) run_interactive ;;
        3) install_service ;;
        4) stop_service ;;
        5) show_logs ;;
        6) uninstall ;;
        0) exit 0 ;;
        *) echo "انتخاب نامعتبر"; sleep 1 ;;
    esac
done