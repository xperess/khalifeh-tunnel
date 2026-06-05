#!/usr/bin/env bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

clear
echo ""
echo "========================================="
echo "   خلیفه تانل - Khalifeh Tunnel v2.0"
echo "========================================="
echo ""
echo "1) اجرای تونل (ایران یا خارج)"
echo "2) توقف تونل"
echo "3) مشاهده وضعیت"
echo "4) مشاهده لاگ"
echo "5) حذف کامل"
echo "0) خروج"
echo ""
read -p "انتخاب: " ch

case $ch in
    1)
        pkill -f khalifeh.py 2>/dev/null
        python3 /opt/khalifeh/khalifeh.py
        ;;
    2)
        pkill -f khalifeh.py
        echo -e "${GREEN}تونل متوقف شد${NC}"
        ;;
    3)
        echo ""
        if pgrep -f khalifeh.py > /dev/null; then
            echo -e "${GREEN}● تونل در حال اجرا است${NC}"
        else
            echo -e "${RED}● تونل متوقف شده است${NC}"
        fi
        echo ""
        echo "پورت‌های باز شده:"
        ss -tlnp | grep -E "LISTEN" | grep -v "127.0.0.1" | awk '{print $4}' | cut -d: -f2 | sort -n | uniq
        ;;
    4)
        journalctl -u khalifeh -f -n 50 2>/dev/null || echo "لاگی موجود نیست"
        ;;
    5)
        read -p "حذف شود؟ (y/n): " confirm
        [[ "$confirm" == "y" ]] && {
            pkill -f khalifeh.py
            rm -rf /opt/khalifeh
            rm -f /usr/local/bin/khalifeh-manager
            echo "حذف شد"
        }
        ;;
    0)
        exit 0
        ;;
esac