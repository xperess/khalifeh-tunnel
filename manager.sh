#!/usr/bin/env bash
set -euo pipefail

# خلیفه تانل - مدیریت ساده

APP_NAME="Khalifeh Tunnel"
VERSION="2.0.0"
PYTHON_SCRIPT="/opt/khalifeh/khalifeh.py"
SERVICE_NAME="khalifeh"

# رنگ‌ها
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    CYAN='\033[0;36m'
    BLUE='\033[0;34m'
    NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; BLUE=''; NC=''
fi

need_root() {
    if [[ "$(id -u)" != "0" ]]; then
        echo -e "${RED}لطفاً با دسترسی روت اجرا کنید: sudo $0${NC}"
        exit 1
    fi
}

show_banner() {
    echo -e "${CYAN}"
    echo "========================================"
    echo "   خلیفه تانل - Khalifeh Tunnel v2.0"
    echo "   مدیریت تونل بین ایران و خارج"
    echo "========================================"
    echo -e "${NC}"
}

show_menu() {
    clear
    show_banner
    echo -e "${GREEN}1)${NC} اجرای تونل (حالت تعاملی)"
    echo -e "${GREEN}2)${NC} توقف تونل"
    echo -e "${GREEN}3)${NC} ریستارت تونل"
    echo -e "${GREEN}4)${NC} مشاهده وضعیت"
    echo -e "${GREEN}5)${NC} مشاهده لاگ‌ها"
    echo -e "${GREEN}6)${NC} اجرا به عنوان سرویس (systemd)"
    echo -e "${GREEN}7)${NC} توقف سرویس"
    echo -e "${GREEN}8)${NC} حذف کامل"
    echo -e "${GREEN}0)${NC} خروج"
    echo ""
    read -p "انتخاب: " choice
}

stop_tunnel() {
    echo -e "${YELLOW}[*] توقف تونل...${NC}"
    pkill -f "khalifeh.py" 2>/dev/null && echo -e "${GREEN}[✓] تونل متوقف شد${NC}" || echo -e "${YELLOW}[!] تونلی در حال اجرا نیست${NC}"
}

restart_tunnel() {
    stop_tunnel
    sleep 1
    echo -e "${GREEN}[*] اجرای مجدد تونل...${NC}"
    python3 /opt/khalifeh/khalifeh.py
}

show_status() {
    echo -e "${CYAN}[*] بررسی وضعیت تونل...${NC}"
    if pgrep -f "khalifeh.py" > /dev/null; then
        echo -e "${GREEN}[✓] تونل در حال اجرا است${NC}"
        echo -e "\n${CYAN}پورت‌های باز شده توسط تونل:${NC}"
        ss -tlnp | grep -E "LISTEN" | grep -v "127.0.0.1" | head -20
    else
        echo -e "${RED}[✗] تونل در حال اجرا نیست${NC}"
    fi
}

show_logs() {
    echo -e "${CYAN}[*] نمایش لاگ‌ها (Ctrl+C برای خروج)...${NC}"
    sleep 1
    journalctl -u $SERVICE_NAME -f -n 50 2>/dev/null || {
        echo -e "${YELLOW}[!] سرویس پیدا نشد، نمایش لاگ از فرآیند...${NC}"
        pkill -f "khalifeh.py" 2>/dev/null
        python3 /opt/khalifeh/khalifeh.py
    }
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
WorkingDirectory=/opt/khalifeh
ExecStart=/usr/bin/python3 /opt/khalifeh/khalifeh.py
Restart=always
RestartSec=5
LimitNOFILE=65535

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
    echo -e "${GREEN}[✓] سرویس متوقف شد${NC}"
    read -p "Enter to continue..."
}

uninstall() {
    echo -e "${RED}[!] حذف کامل خلیفه تانل...${NC}"
    read -p "آیا مطمئن هستید؟ (y/n): " confirm
    if [[ "$confirm" == "y" ]]; then
        stop_service
        rm -f /etc/systemd/system/$SERVICE_NAME.service
        rm -rf /opt/khalifeh
        rm -f /usr/local/bin/khalifeh
        rm -f /usr/local/bin/khalifeh-manager
        rm -f /usr/local/bin/khalifeh-restart
        systemctl daemon-reload
        echo -e "${GREEN}[✓] حذف شد${NC}"
    fi
    read -p "Enter to continue..."
}

# ========== اصلی ==========
need_root

while true; do
    show_menu
    case $choice in
        1) run_interactive ;;
        2) stop_tunnel; read -p "Enter to continue..." ;;
        3) restart_tunnel ;;
        4) show_status; read -p "Enter to continue..." ;;
        5) show_logs ;;
        6) install_service ;;
        7) stop_service ;;
        8) uninstall ;;
        0) exit 0 ;;
        *) echo "انتخاب نامعتبر"; sleep 1 ;;
    esac
done