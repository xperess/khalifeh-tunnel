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
    MAGENTA='\033[0;35m'
    WHITE='\033[1;37m'
    BOLD='\033[1m'
    DIM='\033[2m'
    NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; BLUE=''; MAGENTA=''; WHITE=''; BOLD=''; DIM=''; NC=''
fi

need_root() {
    if [[ "$(id -u)" != "0" ]]; then
        echo -e "${RED}${BOLD}[!] خطا:${NC} ${RED}لطفاً با دسترسی روت اجرا کنید: sudo $0${NC}"
        exit 1
    fi
}

show_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                                                              ║"
    echo "║     ██╗  ██╗ █████╗ ██╗     ██╗███████╗███████╗███████╗     ║"
    echo "║     ██║  ██║██╔══██╗██║     ██║██╔════╝██╔════╝██╔════╝     ║"
    echo "║     ███████║███████║██║     ██║█████╗  █████╗  █████╗       ║"
    echo "║     ██╔══██║██╔══██║██║     ██║██╔══╝  ██╔══╝  ██╔══╝       ║"
    echo "║     ██║  ██║██║  ██║███████╗██║██║     ███████╗███████╗     ║"
    echo "║     ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═╝╚═╝     ╚══════╝╚══════╝     ║"
    echo "║                                                              ║"
    echo "║              ${WHITE}خلیفه تانل - Khalifeh Tunnel${CYAN}                        ║"
    echo "║                      ${DIM}نسخه ${VERSION}${CYAN}                                 ║"
    echo "╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

show_status_bar() {
    if pgrep -f "khalifeh.py" > /dev/null; then
        echo -e " ${GREEN}●${NC} وضعیت: ${GREEN}در حال اجرا${NC}    ${CYAN}├${NC}  $(date)"
    else
        echo -e " ${RED}●${NC} وضعیت: ${RED}متوقف شده${NC}    ${CYAN}├${NC}  $(date)"
    fi
    
    # نمایش تعداد پورت‌های باز شده
    local port_count=$(ss -tlnp 2>/dev/null | grep -c "0.0.0.0:" || echo "0")
    echo -e " ${BLUE}■${NC} پورت‌های باز: ${WHITE}${port_count}${NC}"
    echo ""
}

show_menu() {
    show_banner
    show_status_bar
    
    echo -e " ${GREEN}┌─────────────────────────────────────────────────────────┐${NC}"
    echo -e " ${GREEN}│${NC}  ${BOLD}منوی مدیریت تونل${NC}                                      ${GREEN}│${NC}"
    echo -e " ${GREEN}├─────────────────────────────────────────────────────────┤${NC}"
    echo -e " ${GREEN}│${NC}                                                         ${GREEN}│${NC}"
    echo -e " ${GREEN}│${NC}   ${GREEN}1${NC}) ▶  اجرای تونل (حالت تعاملی)                        ${GREEN}│${NC}"
    echo -e " ${GREEN}│${NC}   ${YELLOW}2${NC}) ■  توقف تونل                                    ${GREEN}│${NC}"
    echo -e " ${GREEN}│${NC}   ${BLUE}3${NC}) ⟳  ریستارت تونل                                  ${GREEN}│${NC}"
    echo -e " ${GREEN}│${NC}   ${CYAN}4${NC}) ℹ   مشاهده وضعیت                                  ${GREEN}│${NC}"
    echo -e " ${GREEN}│${NC}   ${CYAN}5${NC}) 📜  مشاهده لاگ‌ها                                  ${GREEN}│${NC}"
    echo -e " ${GREEN}│${NC}                                                         ${GREEN}│${NC}"
    echo -e " ${GREEN}│${NC}   ${MAGENTA}6${NC}) ⚙   نصب سرویس (systemd)                         ${GREEN}│${NC}"
    echo -e " ${GREEN}│${NC}   ${MAGENTA}7${NC}) ⏹   توقف سرویس                                 ${GREEN}│${NC}"
    echo -e " ${GREEN}│${NC}                                                         ${GREEN}│${NC}"
    echo -e " ${GREEN}│${NC}   ${RED}8${NC}) 🗑   حذف کامل                                    ${GREEN}│${NC}"
    echo -e " ${GREEN}│${NC}   ${WHITE}0${NC}) 🚪  خروج                                        ${GREEN}│${NC}"
    echo -e " ${GREEN}│${NC}                                                         ${GREEN}│${NC}"
    echo -e " ${GREEN}└─────────────────────────────────────────────────────────┘${NC}"
    echo ""
    echo -ne " ${YELLOW}➜${NC} ${BOLD}انتخاب کنید:${NC} "
}

stop_tunnel() {
    echo ""
    echo -e "${YELLOW}${BOLD}[•]${NC} ${YELLOW}در حال توقف تونل...${NC}"
    pkill -f "khalifeh.py" 2>/dev/null && echo -e " ${GREEN}✓${NC} ${GREEN}تونل متوقف شد${NC}" || echo -e " ${DIM}○${NC} ${DIM}تونلی در حال اجرا نیست${NC}"
    echo ""
    read -p "Enter to continue..."
}

restart_tunnel() {
    echo ""
    echo -e "${BLUE}${BOLD}[•]${NC} ${BLUE}در حال ریستارت تونل...${NC}"
    pkill -f "khalifeh.py" 2>/dev/null
    sleep 1
    echo -e " ${GREEN}✓${NC} ${GREEN}تونل مجدداً اجرا شد${NC}"
    python3 /opt/khalifeh/khalifeh.py
}

show_status() {
    echo ""
    echo -e "${CYAN}${BOLD}┌─────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│${NC}  ${BOLD}وضعیت سیستم${NC}                                              ${CYAN}│${NC}"
    echo -e "${CYAN}├─────────────────────────────────────────────────────────┤${NC}"
    
    if pgrep -f "khalifeh.py" > /dev/null; then
        local pid=$(pgrep -f "khalifeh.py" | head -1)
        echo -e "${CYAN}│${NC}  ${GREEN}● تونل: در حال اجرا${NC} (PID: $pid)                    ${CYAN}│${NC}"
    else
        echo -e "${CYAN}│${NC}  ${RED}● تونل: متوقف شده${NC}                                    ${CYAN}│${NC}"
    fi
    
    echo -e "${CYAN}├─────────────────────────────────────────────────────────┤${NC}"
    echo -e "${CYAN}│${NC}  ${BOLD}پورت‌های باز شده توسط تونل:${NC}                            ${CYAN}│${NC}"
    
    local ports=$(ss -tlnp 2>/dev/null | grep -E "LISTEN" | grep -v "127.0.0.1" | awk '{print $4}' | cut -d: -f2 | sort -n | uniq | head -15)
    if [[ -n "$ports" ]]; then
        local count=0
        for p in $ports; do
            if [[ $count -ge 10 ]]; then
                echo -e "${CYAN}│${NC}  ${DIM}... و پورت‌های بیشتر${NC}                                 ${CYAN}│${NC}"
                break
            fi
            echo -e "${CYAN}│${NC}    ${GREEN}→${NC} پورت ${WHITE}$p${NC}                                           ${CYAN}│${NC}"
            ((count++))
        done
    else
        echo -e "${CYAN}│${NC}    ${DIM}هیچ پورتی باز نشده${NC}                                     ${CYAN}│${NC}"
    fi
    
    echo -e "${CYAN}└─────────────────────────────────────────────────────────┘${NC}"
    echo ""
    read -p "Enter to continue..."
}

show_logs() {
    echo ""
    echo -e "${CYAN}${BOLD}[•]${NC} ${CYAN}نمایش لاگ‌ها (Ctrl+C برای خروج)...${NC}"
    echo ""
    sleep 1
    journalctl -u $SERVICE_NAME -f -n 50 2>/dev/null || {
        echo -e "${YELLOW}${BOLD}[!]${NC} ${YELLOW}سرویس یافت نشد، اجرای مستقیم...${NC}"
        python3 /opt/khalifeh/khalifeh.py
    }
}

run_interactive() {
    echo ""
    echo -e "${GREEN}${BOLD}[•]${NC} ${GREEN}در حال اجرای تونل...${NC}"
    echo ""
    python3 /opt/khalifeh/khalifeh.py
}

install_service() {
    echo ""
    echo -e "${MAGENTA}${BOLD}[•]${NC} ${MAGENTA}در حال نصب سرویس systemd...${NC}"
    
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
    
    echo -e " ${GREEN}✓${NC} ${GREEN}سرویس با موفقیت نصب و راه‌اندازی شد${NC}"
    echo -e " ${DIM}وضعیت: systemctl status $SERVICE_NAME${NC}"
    echo ""
    read -p "Enter to continue..."
}

stop_service() {
    echo ""
    echo -e "${YELLOW}${BOLD}[•]${NC} ${YELLOW}در حال توقف سرویس...${NC}"
    systemctl stop $SERVICE_NAME 2>/dev/null || true
    systemctl disable $SERVICE_NAME 2>/dev/null || true
    pkill -f "khalifeh.py" 2>/dev/null || true
    echo -e " ${GREEN}✓${NC} ${GREEN}سرویس متوقف شد${NC}"
    echo ""
    read -p "Enter to continue..."
}

uninstall() {
    echo ""
    echo -e "${RED}${BOLD}[!]${NC} ${RED}حذف کامل خلیفه تانل${NC}"
    echo -e "${RED}┌─────────────────────────────────────────────────────────┐${NC}"
    echo -e "${RED}│${NC}  ${YELLOW}آیا از حذف کامل اطمینان دارید؟${NC}                           ${RED}│${NC}"
    echo -e "${RED}│${NC}  ${DIM}این عمل همه فایل‌ها و تنظیمات را پاک می‌کند${NC}                 ${RED}│${NC}"
    echo -e "${RED}└─────────────────────────────────────────────────────────┘${NC}"
    echo ""
    read -p "آیا مطمئن هستید؟ (y/n): " confirm
    if [[ "$confirm" == "y" ]]; then
        stop_service >/dev/null 2>&1
        rm -f /etc/systemd/system/$SERVICE_NAME.service
        rm -rf /opt/khalifeh
        rm -f /usr/local/bin/khalifeh
        rm -f /usr/local/bin/khalifeh-manager
        rm -f /usr/local/bin/khalifeh-restart
        systemctl daemon-reload
        echo -e " ${GREEN}✓${NC} ${GREEN}خلیفه تانل با موفقیت حذف شد${NC}"
    else
        echo -e " ${DIM}○${NC} ${DIM}عملیات لغو شد${NC}"
    fi
    echo ""
    read -p "Enter to continue..."
}

# ========== اصلی ==========
need_root

while true; do
    show_menu
    read -r choice
    case $choice in
        1) run_interactive ;;
        2) stop_tunnel ;;
        3) restart_tunnel ;;
        4) show_status ;;
        5) show_logs ;;
        6) install_service ;;
        7) stop_service ;;
        8) uninstall ;;
        0) 
            echo ""
            echo -e "${GREEN}${BOLD}خداحافظ!${NC}"
            echo ""
            exit 0 
            ;;
        *) 
            echo ""
            echo -e "${RED}${BOLD}[!]${NC} ${RED}انتخاب نامعتبر${NC}"
            sleep 1 
            ;;
    esac
done