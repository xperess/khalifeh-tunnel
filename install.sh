#!/bin/bash
# نصب خودکار خلیفه تانل

set -e

echo "==================================="
echo "   نصب خلیفه تانل - Khalifeh Tunnel"
echo "==================================="

# بررسی دسترسی روت
if [[ "$EUID" -ne 0 ]]; then
    echo "لطفاً با دسترسی روت اجرا کنید: sudo bash install.sh"
    exit 1
fi

# دریافت فایل‌ها
echo "[*] دانلود فایل‌ها..."

REPO_URL="https://raw.githubusercontent.com/xperess/khalifeh-tunnel/main"

curl -s -o /tmp/khalifeh.py "$REPO_URL/khalifeh.py"
curl -s -o /tmp/manager.sh "$REPO_URL/manager.sh"

# نصب
mkdir -p /opt/khalifeh
cp /tmp/khalifeh.py /opt/khalifeh/
cp /tmp/manager.sh /usr/local/bin/khalifeh-manager
chmod +x /opt/khalifeh/khalifeh.py
chmod +x /usr/local/bin/khalifeh-manager

# وابستگی‌ها
apt-get update -y
apt-get install -y python3 screen iproute2

# لینک سریع
ln -sf /opt/khalifeh/khalifeh.py /usr/local/bin/khalifeh 2>/dev/null || true

echo ""
echo "✅ نصب کامل شد!"
echo ""
echo "برای مدیریت تونل:"
echo "   sudo khalifeh-manager"
echo ""
echo "برای اجرای مستقیم:"
echo "   sudo khalifeh"