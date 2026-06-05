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

# اصلاح فرمت فایل‌ها (حذف \r)
sed -i 's/\r$//' /opt/khalifeh/khalifeh.py
sed -i 's/\r$//' /usr/local/bin/khalifeh-manager

# افزایش محدودیت فایل‌ها
echo "root soft nofile 65535" >> /etc/security/limits.conf
echo "root hard nofile 65535" >> /etc/security/limits.conf

# وابستگی‌ها
apt-get update -y 2>/dev/null || true
apt-get install -y python3 screen iproute2

# لینک سریع
ln -sf /opt/khalifeh/khalifeh.py /usr/local/bin/khalifeh 2>/dev/null || true

# اسکریپت ریستارت
cat > /usr/local/bin/khalifeh-restart << 'EOF'
#!/bin/bash
pkill -f khalifeh.py 2>/dev/null
sleep 1
sudo khalifeh
EOF
chmod +x /usr/local/bin/khalifeh-restart

echo ""
echo "✅ نصب کامل شد!"
echo ""
echo "برای مدیریت تونل:"
echo "   sudo khalifeh-manager"
echo ""
echo "برای اجرای مستقیم:"
echo "   sudo khalifeh"
echo ""
echo "برای ریستارت سریع:"
echo "   sudo khalifeh-restart"