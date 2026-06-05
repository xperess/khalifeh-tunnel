نصب نهایی:
bash
curl -s -O https://raw.githubusercontent.com/xperess/khalifeh-tunnel/main/install.sh
sed -i 's/\r$//' install.sh && sudo bash install.sh
بعد از نصب:

bash
sudo khalifeh
منو به این شکل نمایش داده می‌شود:

text
=========================================
   Khalifeh Tunnel Manager v2.0
=========================================

  PROFILES:
  ---------
  [STOPPED] 1) Iran Default (server)

  OPTIONS:
  --------
  N) Create new profile
  E) Edit profile
  D) Delete profile
  R) Run profile
  S) Stop profile
  L) View logs
  X) Manage excluded ports
  U) Uninstall
  Q) Quit

