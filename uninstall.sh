#!/bin/bash
# حذف خلیفه تانل

set -e

if [[ "$EUID" -ne 0 ]]; then
    echo "لطفاً با دسترسی روت اجرا کنید"
    exit 1
fi

echo "حذف خلیفه تانل..."

# توقف سرویس
systemctl stop khalifeh 2>/dev/null || true
systemctl disable khalifeh 2>/dev/null || true

# حذف فایل‌ها
rm -rf /opt/khalifeh
rm -f /usr/local/bin/khalifeh
rm -f /usr/local/bin/khalifeh-manager
rm -f /etc/systemd/system/khalifeh.service

systemctl daemon-reload

echo "✅ حذف شد"